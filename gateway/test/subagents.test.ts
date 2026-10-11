import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { Semaphore } from "../src/subagents/semaphore.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;
type Message = { role: string; content: unknown; toolsAdded?: { name: string }[] };
type Seen = { prompt: string; tools: string[]; system: string };

function lastUserText(messages: Message[]): string {
	const user = [...messages].reverse().find((message) => message.role === "user");
	return typeof user?.content === "string" ? user.content : "";
}

function inspectRequest(messages: Message[]): Seen {
	const head = messages.find((message) => message.role === "system");
	return {
		prompt: lastUserText(messages),
		tools: (head?.toolsAdded ?? []).map((tool) => tool.name).sort(),
		system: JSON.stringify(head ?? {}),
	};
}

async function parentCall(harness: Harness, tool: string, args: Record<string, string | string[]>, responses: unknown[]) {
	const { faux, gateway, outgoing } = harness;
	faux.setResponses([
		fauxAssistantMessage(fauxToolCall(tool, args), { stopReason: "toolUse" }),
		...(responses as never[]),
		fauxAssistantMessage("finished"),
	]);
	await gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir() });
	const { conversationId } = (reply(outgoing, "c") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "a", type: "attach", conversationId });
	await gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => hasEvent(outgoing, "run_end"));
	return conversationId;
}

function toolResultText(harness: Harness): string {
	const snapshotText = JSON.stringify(harness.outgoing.filter((message) => message.type === "events"));
	const match = /"role":"toolResult"[^]*?"text":"((?:[^"\\]|\\.)*)"/.exec(snapshotText);
	return JSON.parse(`"${match?.[1] ?? ""}"`);
}

test("every prompt gets its own subagent and the answers come back in prompt order", async () => {
	// Arrange
	const harness = await setup(undefined, 6);
	const seen: Seen[] = [];
	const child = (context: { messages: Message[] }) => {
		seen.push(inspectRequest(context.messages));
		return fauxAssistantMessage(`echo:${lastUserText(context.messages)}`);
	};

	// Act
	await parentCall(harness, "agent", { prompts: ["a", "b", "c"] }, [child, child, child]);

	// Assert
	assert.deepEqual(JSON.parse(toolResultText(harness)), ["echo:a", "echo:b", "echo:c"]);
	assert.deepEqual(seen.map((request) => request.prompt).sort(), ["a", "b", "c"]);
	await harness.close();
});

test("no more subagents run at once than the limit allows", async () => {
	// Arrange
	const harness = await setup(undefined, 2);
	let active = 0;
	let peak = 0;
	const child = async (context: { messages: Message[] }) => {
		active += 1;
		peak = Math.max(peak, active);
		await new Promise((resolve) => setTimeout(resolve, 30));
		active -= 1;
		return fauxAssistantMessage(`echo:${lastUserText(context.messages)}`);
	};
	const prompts = ["1", "2", "3", "4", "5"];

	// Act
	await parentCall(harness, "agent", { prompts }, prompts.map(() => child));

	// Assert
	assert.equal(peak, 2);
	assert.deepEqual(JSON.parse(toolResultText(harness)), prompts.map((prompt) => `echo:${prompt}`));
	await harness.close();
});

test("subagents do not appear in the session list and cannot start subagents themselves", async () => {
	// Arrange
	const harness = await setup(undefined, 6);
	const seen: Seen[] = [];
	const child = (context: { messages: Message[] }) => {
		seen.push(inspectRequest(context.messages));
		return fauxAssistantMessage("ok");
	};

	// Act
	const parentId = await parentCall(harness, "agent", { prompts: ["x"] }, [child]);
	await harness.gateway.handle({ id: "l", type: "list_conversations" });

	// Assert
	const listed = reply(harness.outgoing, "l") as { result: { conversations: { id: number }[] } };
	assert.deepEqual(listed.result.conversations.map((conversation) => conversation.id), [parentId]);
	assert.ok(seen[0]?.tools.includes("bash"));
	assert.ok(!seen[0]?.tools.includes("agent"));
	await harness.close();
});

test("a persona shapes the subagent and an unknown persona is reported without running anything", async () => {
	// Arrange
	const harness = await setup(undefined, 6);
	await writeFile(`${harness.personasDir}/reader.md`, "---\nname: reader\ntools: Read\n---\nOnly read; never edit.");
	const seen: Seen[] = [];
	const child = (context: { messages: Message[] }) => {
		seen.push(inspectRequest(context.messages));
		return fauxAssistantMessage("ok");
	};

	// Act
	await parentCall(harness, "agent", { prompts: ["look"], persona: "reader" }, [child]);
	const unknown = await setup(undefined, 6);
	await parentCall(unknown, "agent", { prompts: ["look"], persona: "ghost" }, []);

	// Assert
	assert.deepEqual(seen[0]?.tools, ["codemode", "read"]);
	assert.match(seen[0]?.system ?? "", /Only read; never edit\./);
	assert.match(toolResultText(unknown), /unknown persona ghost/);
	await harness.close();
	await unknown.close();
});

test("a script can fan out to subagents and combine their answers in one tool call", async () => {
	// Arrange
	const harness = await setup(undefined, 6);
	const child = (context: { messages: Message[] }) => fauxAssistantMessage(`echo:${lastUserText(context.messages)}`);
	const code = 'const answers = JSON.parse(await tools.agent({ prompts: ["x", "y"] })); text(answers.join("+"));';

	// Act
	await parentCall(harness, "codemode", { code }, [child, child]);

	// Assert
	assert.match(toolResultText(harness), /echo:x\+echo:y/);
	await harness.close();
});

test("the semaphore hands out permits in order and a failed job frees its permit", async () => {
	// Arrange
	const semaphore = new Semaphore(1);
	const order: string[] = [];
	const job = (name: string, fail = false) =>
		semaphore.run(async () => {
			order.push(name);
			await new Promise((resolve) => setTimeout(resolve, 5));
			if (fail) throw new Error(name);
		});

	// Act
	const results = await Promise.allSettled([job("a"), job("b", true), job("c")]);

	// Assert
	assert.deepEqual(order, ["a", "b", "c"]);
	assert.deepEqual(
		results.map((result) => result.status),
		["fulfilled", "rejected", "fulfilled"],
	);
});

test("a subagent's permission prompt goes to the parent conversation and names the subagent", async () => {
	// Arrange
	const harness = await setup({ mode: "ask", allow: [], ask: [], deny: [] }, 6);
	const child = (context: { messages: Message[] }) => {
		const last = context.messages[context.messages.length - 1];
		if (last?.role === "toolResult") return fauxAssistantMessage("child done");
		return fauxAssistantMessage(fauxToolCall("bash", { command: "make deploy" }), { stopReason: "toolUse" });
	};
	const parent = parentCall(harness, "agent", { prompts: ["deploy"] }, [child, child]);

	// Act
	await waitFor(() => harness.outgoing.some((message) => message.type === "permission_request"));
	const request = harness.outgoing.find((message) => message.type === "permission_request") as {
		requestId: string;
		conversationId: number;
		subagent?: number;
		summary: string;
	};
	await harness.gateway.handle({ id: "p", type: "permission_reply", requestId: request.requestId, approval: "deny" });
	const parentId = await parent;

	// Assert
	assert.equal(request.conversationId, parentId);
	assert.equal(typeof request.subagent, "number");
	assert.notEqual(request.subagent, parentId);
	assert.equal(request.summary, "make deploy");
	await harness.close();
});
