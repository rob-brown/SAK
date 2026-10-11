import assert from "node:assert/strict";
import { access, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { parseRule, type Policy } from "../src/permissions/rules.ts";
import type { Outgoing } from "../src/protocol.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;
type Message = { role: string; content: unknown };
type Request = Extract<Outgoing, { type: "permission_request" }>;

const ASK: Policy = { mode: "ask", allow: [], ask: [], deny: [] };

function requests(outgoing: Outgoing[]) {
	return outgoing.filter((message): message is Request => message.type === "permission_request");
}

async function exists(path: string) {
	return access(path).then(
		() => true,
		() => false,
	);
}

async function marker() {
	return join(await mkdtemp(join(tmpdir(), "sak-persona-perm-")), "ran");
}

async function withBuilder(harness: Harness) {
	await writeFile(join(harness.personasDir, "builder.md"), "---\nname: builder\ntools: Bash(touch *)\n---\nBuild things.");
}

async function run(harness: Harness, command: string, persona?: string) {
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("bash", { command }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir(), ...(persona ? { persona } : {}) });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => requests(harness.outgoing).length > 0 || hasEvent(harness.outgoing, "run_end"));
}

async function deny(harness: Harness) {
	const request = requests(harness.outgoing)[0] as Request;
	await harness.gateway.handle({ id: "r", type: "permission_reply", requestId: request.requestId, approval: "deny" });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
}

test("a command the persona names runs without a prompt, and other commands still ask", async () => {
	// Arrange
	const harness = await setup(ASK);
	await withBuilder(harness);
	const allowed = await marker();

	// Act
	await run(harness, `touch ${allowed}`, "builder");
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	const other = await setup(ASK);
	await withBuilder(other);
	await run(other, "echo hi", "builder");
	const asked = requests(other.outgoing)[0];
	await deny(other);

	// Assert
	assert.equal(await exists(allowed), true);
	assert.equal(requests(harness.outgoing).length, 0);
	assert.equal(asked?.summary, "echo hi");
	await harness.close();
	await other.close();
});

test("the rules belong to the persona: a session without it still asks, and a deny rule in the config wins", async () => {
	// Arrange
	const plain = await setup(ASK);
	await withBuilder(plain);
	const denying = await setup({ ...ASK, deny: [parseRule("Bash(touch *)")] });
	await withBuilder(denying);
	const first = await marker();
	const second = await marker();

	// Act
	await run(plain, `touch ${first}`);
	const asked = requests(plain.outgoing)[0];
	await deny(plain);
	await run(denying, `touch ${second}`, "builder");
	await waitFor(() => hasEvent(denying.outgoing, "run_end"));

	// Assert
	assert.equal(asked?.summary, `touch ${first}`);
	assert.equal(await exists(second), false);
	assert.equal(requests(denying.outgoing).length, 0);
	assert.match(JSON.stringify(denying.outgoing), /Permission denied by a rule/);
	await plain.close();
	await denying.close();
});

test("a subagent follows the rules of its own persona, not the parent's", async () => {
	// Arrange
	const harness = await setup(ASK, 6);
	await withBuilder(harness);
	await writeFile(join(harness.personasDir, "plain.md"), "---\nname: plain\ntools: Bash\n---\nPlain.");
	const built = await marker();
	const blocked = await marker();
	const child = (path: string) => (context: { messages: Message[] }) => {
		const last = context.messages[context.messages.length - 1];
		if (last?.role === "toolResult") return fauxAssistantMessage("child done");
		return fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${path}` }), { stopReason: "toolUse" });
	};
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("agent", { prompts: ["build"], persona: "builder" }), { stopReason: "toolUse" }),
		child(built),
		child(built),
		fauxAssistantMessage(fauxToolCall("agent", { prompts: ["plain"], persona: "plain" }), { stopReason: "toolUse" }),
		child(blocked),
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir() });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => requests(harness.outgoing).length > 0);
	const asked = requests(harness.outgoing)[0];

	// Assert
	assert.equal(await exists(built), true);
	assert.equal(asked?.summary, `touch ${blocked}`);
	assert.equal(typeof asked?.subagent, "number");
	assert.equal(await exists(blocked), false);
	await deny(harness);
	await harness.close();
});
