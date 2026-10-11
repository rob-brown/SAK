import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { collapseSystemMessages } from "@earendil-works/pi-ai/utils/transcript";
import type { Gateway } from "../src/gateway.ts";
import type { Command, Outgoing } from "../src/protocol.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

test("create_conversation then list_conversations returns the new conversation", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();

	// Act
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp" });
	await gateway.handle({ id: "2", type: "list_conversations" });

	// Assert
	const created = reply(outgoing, "1") as { result: { conversationId: number } };
	const listed = reply(outgoing, "2") as { result: { conversations: { id: number; cwd: string | null }[] } };
	assert.deepEqual(
		listed.result.conversations.map((conversation) => [conversation.id, conversation.cwd]),
		[[created.result.conversationId, "/tmp"]],
	);
	await close();
});

test("attach sends a snapshot, then submit streams events through run_end", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	faux.setResponses([fauxAssistantMessage("hello there")]);
	await gateway.handle({ id: "1", type: "create_conversation" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;

	// Act
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "3", type: "submit", conversationId, content: "hi" });
	await waitFor(() => hasEvent(outgoing, "run_end"));

	// Assert
	const snapshotIndex = outgoing.findIndex((message) => message.type === "snapshot");
	const firstEventsIndex = outgoing.findIndex((message) => message.type === "events");
	assert.ok(snapshotIndex >= 0 && snapshotIndex < firstEventsIndex);
	assert.equal((reply(outgoing, "3") as { ok: boolean }).ok, true);
	assert.match(JSON.stringify(outgoing), /hello there/);
	await close();
});

test("a command for an unknown conversation replies with an error", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();
	const command: Command = { id: "1", type: "attach", conversationId: 9999 };

	// Act
	await gateway.handle(command);

	// Assert
	assert.deepEqual(reply(outgoing, "1"), {
		type: "reply",
		id: "1",
		ok: false,
		error: "unknown conversation 9999",
	});
	await close();
});

test("attaching twice sends a fresh snapshot each time", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();
	await gateway.handle({ id: "1", type: "create_conversation" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;

	// Act
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "3", type: "attach", conversationId });

	// Assert
	assert.equal(outgoing.filter((message) => message.type === "snapshot").length, 2);
	await close();
});

test("fork keeps the entries up to and including the chosen one and carries the name", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	faux.setResponses([fauxAssistantMessage("first answer"), fauxAssistantMessage("second answer")]);
	await gateway.handle({ id: "1", type: "create_conversation", name: "Parent" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "3", type: "submit", conversationId, content: "one" });
	await waitFor(() => outgoing.filter((m) => m.type === "events" && JSON.stringify(m).includes("run_end")).length >= 1);
	await gateway.handle({ id: "4", type: "submit", conversationId, content: "two" });
	await waitFor(() => outgoing.filter((m) => m.type === "events" && JSON.stringify(m).includes("run_end")).length >= 2);
	await gateway.handle({ id: "5", type: "attach", conversationId });
	const parent = outgoing.filter((m) => m.type === "snapshot").pop() as { snapshot: { entries: { id: number }[] } };
	const firstAnswer = parent.snapshot.entries.find((e) => JSON.stringify(e).includes("first answer")) as { id: number };

	// Act
	await gateway.handle({ id: "6", type: "fork", conversationId, at: firstAnswer.id });
	const forkId = (reply(outgoing, "6") as { result: { conversationId: number } }).result.conversationId;
	await gateway.handle({ id: "7", type: "attach", conversationId: forkId });
	await gateway.handle({ id: "8", type: "list_conversations" });

	// Assert
	const forked = outgoing.filter((m) => m.type === "snapshot").pop() as { snapshot: { entries: unknown[] } };
	const text = JSON.stringify(forked.snapshot.entries);
	assert.ok(text.includes("first answer"));
	assert.ok(!text.includes('"content":"two"'));
	assert.ok(!text.includes("second answer"));
	const listed = reply(outgoing, "8") as Listed;
	assert.equal(listed.result.conversations.find((c) => c.id === forkId)?.name, "Parent (fork)");
	await close();
});

async function systemEntry(gateway: Gateway, outgoing: Outgoing[], conversationId: number, id: string) {
	await gateway.handle({ id, type: "attach", conversationId });
	const snapshot = outgoing.filter((m) => m.type === "snapshot").pop() as {
		snapshot: { entries: { kind: string; model: { toolsAdded?: { name: string }[]; sections?: unknown }[] }[] };
	};
	return snapshot.snapshot.entries.find((entry) => entry.kind === "pi.system");
}

test("the default persona offers every tool including codemode and the Pi-style prompt", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	faux.setResponses([fauxAssistantMessage("hello")]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "5", type: "submit", conversationId, content: "hi" });
	await waitFor(() => hasEvent(outgoing, "run_end"));

	// Act
	const system = await systemEntry(gateway, outgoing, conversationId, "3");
	await gateway.handle({ id: "4", type: "list_conversations" });

	// Assert
	const tools = (system?.model[0]?.toolsAdded ?? []).map((tool) => tool.name).sort();
	assert.deepEqual(tools, ["bash", "codemode", "edit", "read", "write"]);
	assert.match(JSON.stringify(system), /expert coding assistant/);
	assert.equal((reply(outgoing, "4") as Listed).result.conversations[0]?.persona, "default");
	await close();
});

test("a persona restricts the tools but keeps codemode, and its body becomes the prompt", async () => {
	// Arrange
	const { close, faux, gateway, outgoing, personasDir } = await setup();
	await writeFile(join(personasDir, "reader.md"), "---\nname: reader\ntools: Read\n---\nOnly read; never edit.");
	faux.setResponses([fauxAssistantMessage("hello")]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp", persona: "reader" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "5", type: "submit", conversationId, content: "hi" });
	await waitFor(() => hasEvent(outgoing, "run_end"));

	// Act
	const system = await systemEntry(gateway, outgoing, conversationId, "3");
	await gateway.handle({ id: "4", type: "list_conversations" });

	// Assert
	const tools = (system?.model[0]?.toolsAdded ?? []).map((tool) => tool.name).sort();
	assert.deepEqual(tools, ["codemode", "read"]);
	assert.match(JSON.stringify(system), /Only read; never edit\./);
	assert.doesNotMatch(JSON.stringify(system), /expert coding assistant/);
	assert.equal((reply(outgoing, "4") as Listed).result.conversations[0]?.persona, "reader");
	await close();
});

test("list_personas re-reads the directory each time and an unknown persona is an error", async () => {
	// Arrange
	const { close, gateway, outgoing, personasDir } = await setup();
	await gateway.handle({ id: "1", type: "list_personas" });
	await writeFile(join(personasDir, "late.md"), "---\nname: late\ndescription: Added later\n---\nBody");

	// Act
	await gateway.handle({ id: "2", type: "list_personas" });
	await gateway.handle({ id: "3", type: "create_conversation", persona: "ghost" });

	// Assert
	type Listed = { result: { personas: { name: string; description: string }[] } };
	assert.deepEqual((reply(outgoing, "1") as Listed).result.personas.map((p) => p.name), ["default"]);
	assert.deepEqual((reply(outgoing, "2") as Listed).result.personas.map((p) => p.name), ["default", "late"]);
	assert.equal((reply(outgoing, "3") as { ok: boolean }).ok, false);
	await close();
});

test("the codemode tool runs a script that calls the other tools and returns only its output", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	const code = "const out = await tools.bash({ command: 'echo from-sandbox' }); text(out.trim()); return 40 + 2;";
	faux.setResponses([
		fauxAssistantMessage(fauxToolCall("codemode", { code }), { stopReason: "toolUse" }),
		fauxAssistantMessage("finished"),
	]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;

	// Act
	await gateway.handle({ id: "9", type: "attach", conversationId });
	await gateway.handle({ id: "2", type: "submit", conversationId, content: "go" });
	await waitFor(() => JSON.stringify(outgoing).includes("finished"));
	await gateway.handle({ id: "3", type: "attach", conversationId });

	// Assert
	const snapshot = outgoing.filter((m) => m.type === "snapshot").pop() as { snapshot: { entries: unknown[] } };
	const result = snapshot.snapshot.entries.find((entry) => (entry as { kind: string }).kind === "pi.tool-result");
	const text = JSON.stringify(result);
	assert.match(text, /Script completed/);
	assert.match(text, /from-sandbox/);
	assert.match(text, /42/);
	await close();
});

test("a failing script reports the error instead of throwing", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	faux.setResponses([
		fauxAssistantMessage(fauxToolCall("codemode", { code: "await tools.read({ path: '/definitely/not/here' });" }), {
			stopReason: "toolUse",
		}),
		fauxAssistantMessage("saw the failure"),
	]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp" });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;

	// Act
	await gateway.handle({ id: "9", type: "attach", conversationId });
	await gateway.handle({ id: "2", type: "submit", conversationId, content: "go" });
	await waitFor(() => JSON.stringify(outgoing).includes("saw the failure"));
	await gateway.handle({ id: "3", type: "attach", conversationId });

	// Assert
	const snapshot = outgoing.filter((m) => m.type === "snapshot").pop() as { snapshot: { entries: unknown[] } };
	const result = snapshot.snapshot.entries.find((entry) => (entry as { kind: string }).kind === "pi.tool-result");
	assert.match(JSON.stringify(result), /Script failed/);
	await close();
});

test("editing an instruction file mid-conversation is ignored so the request prefix stays cacheable", async () => {
	// Arrange
	const { close, faux, gateway, outgoing } = await setup();
	const project = await mkdtemp(join(tmpdir(), "sak-project-"));
	const file = join(project, "AGENTS.md");
	await writeFile(file, "Always answer in French.");
	const requests: unknown[][] = [];
	const respond = () => (context: { messages: unknown[] }) => {
		requests.push(collapseSystemMessages({ messages: structuredClone(context.messages) } as never).messages);
		return fauxAssistantMessage("ok");
	};
	faux.setResponses([respond(), respond(), respond()]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: project });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "2", type: "attach", conversationId });

	// Act
	await gateway.handle({ id: "3", type: "submit", conversationId, content: "one" });
	await waitFor(() => requests.length === 1);
	await waitFor(() => hasEvent(outgoing, "run_end"));
	await gateway.handle({ id: "4", type: "submit", conversationId, content: "two" });
	await waitFor(() => requests.length === 2);
	await waitFor(() => outgoing.filter((m) => JSON.stringify(m).includes("run_end")).length >= 2);
	await writeFile(file, "Always answer in German.");
	await gateway.handle({ id: "5", type: "submit", conversationId, content: "three" });
	await waitFor(() => requests.length === 3);

	// Assert
	const [first, second, third] = requests as [unknown[], unknown[], unknown[]];
	assert.match(JSON.stringify(first), /Always answer in French\./);
	assert.deepEqual(second.slice(0, first.length), first);
	assert.deepEqual(third.slice(0, second.length), second);
	assert.ok(first.length >= 2 && third.length > second.length);
	assert.doesNotMatch(JSON.stringify(third), /German/);
	await close();
});

async function skillRequests(setupResult: Awaited<ReturnType<typeof setup>>, persona?: string) {
	const { faux, gateway, outgoing } = setupResult;
	const project = await mkdtemp(join(tmpdir(), "sak-skill-project-"));
	const skillDir = join(project, ".agents", "skills", "pdf");
	await mkdir(skillDir, { recursive: true });
	await writeFile(join(skillDir, "SKILL.md"), "---\nname: pdf\ndescription: Fill PDF forms\n---\nBody");
	const requests: unknown[][] = [];
	const respond = () => (context: { messages: unknown[] }) => {
		requests.push(collapseSystemMessages({ messages: structuredClone(context.messages) } as never).messages);
		return fauxAssistantMessage("ok");
	};
	faux.setResponses([respond(), respond()]);
	await gateway.handle({ id: "1", type: "create_conversation", cwd: project, ...(persona ? { persona } : {}) });
	const { conversationId } = (reply(outgoing, "1") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "2", type: "attach", conversationId });
	await gateway.handle({ id: "3", type: "submit", conversationId, content: "one" });
	await waitFor(() => requests.length === 1);
	await waitFor(() => hasEvent(outgoing, "run_end"));
	await writeFile(join(skillDir, "SKILL.md"), "---\nname: pdf\ndescription: Edited later\n---\nBody");
	await mkdir(join(project, ".agents", "skills", "late"), { recursive: true });
	await writeFile(join(project, ".agents", "skills", "late", "SKILL.md"), "---\nname: late\ndescription: Added later\n---\n");
	await gateway.handle({ id: "4", type: "submit", conversationId, content: "two" });
	await waitFor(() => requests.length === 2);
	return requests as [unknown[], unknown[]];
}

test("skills are listed in the first request and later edits or additions are ignored", async () => {
	// Arrange
	const harness = await setup();

	// Act
	const [first, second] = await skillRequests(harness);

	// Assert
	assert.match(JSON.stringify(first), /<skill name=\\"pdf\\"[^>]*>Fill PDF forms<\/skill>/);
	assert.deepEqual(second.slice(0, first.length), first);
	assert.doesNotMatch(JSON.stringify(second), /Edited later|Added later/);
	await harness.close();
});

test("a persona without the read tool gets no skills section", async () => {
	// Arrange
	const harness = await setup();
	await writeFile(join(harness.personasDir, "shell.md"), "---\nname: shell\ntools: Bash\n---\nShell only.");

	// Act
	const [first] = await skillRequests(harness, "shell");

	// Assert
	assert.doesNotMatch(JSON.stringify(first), /<skills>/);
	await harness.close();
});

test("set_model switches one conversation and leaves the others alone", async () => {
	// Arrange
	const { close, ensured, gateway, outgoing } = await setup();
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp" });
	await gateway.handle({ id: "2", type: "create_conversation", cwd: "/tmp" });
	const first = (reply(outgoing, "1") as { result: { conversationId: number } }).result.conversationId;

	// Act
	await gateway.handle({ id: "3", type: "set_model", conversationId: first, modelId: "other" });
	await gateway.handle({ id: "4", type: "list_conversations" });

	// Assert
	const listed = reply(outgoing, "4") as { result: { conversations: { id: number; model: string }[] } };
	const models = Object.fromEntries(listed.result.conversations.map((c) => [c.id, c.model.split("/").pop()]));
	assert.equal(models[first], "other");
	assert.equal(Object.values(models).filter((model) => model === "other").length, 1);
	assert.deepEqual(ensured, ["other"]);
	await close();
});

test("set_model without a conversation changes the default for new ones", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();

	// Act
	await gateway.handle({ id: "1", type: "set_model", modelId: "other" });
	await gateway.handle({ id: "2", type: "list_models" });
	await gateway.handle({ id: "3", type: "create_conversation", cwd: "/tmp" });
	await gateway.handle({ id: "4", type: "list_conversations" });

	// Assert
	const current = (reply(outgoing, "2") as { result: { current: { modelId: string } } }).result.current;
	const listed = reply(outgoing, "4") as { result: { conversations: { model: string }[] } };
	assert.equal(current.modelId, "other");
	assert.ok(listed.result.conversations[0]?.model.endsWith("/other"));
	await close();
});

type Listed = {
	result: { conversations: { id: number; name: string | null; persona: string | null; state: string; model: string }[] };
};

test("a new conversation can be created with a model and a name", async () => {
	// Arrange
	const { close, ensured, gateway, outgoing } = await setup();

	// Act
	await gateway.handle({ id: "1", type: "create_conversation", cwd: "/tmp", modelId: "other", name: "  Refactor  " });
	await gateway.handle({ id: "2", type: "list_conversations" });

	// Assert
	const [listed] = (reply(outgoing, "2") as Listed).result.conversations;
	assert.equal(listed?.name, "Refactor");
	assert.equal(listed?.state, "active");
	assert.ok(listed?.model.endsWith("/other"));
	assert.deepEqual(ensured, ["other"]);
	await close();
});

test("archived conversations stay listed with their state and deleted ones disappear", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();
	for (const id of ["1", "2", "3"]) await gateway.handle({ id, type: "create_conversation" });
	const ids = ["1", "2", "3"].map((id) => (reply(outgoing, id) as { result: { conversationId: number } }).result.conversationId);

	// Act
	await gateway.handle({ id: "4", type: "set_meta", conversationId: ids[1] as number, state: "archived" });
	await gateway.handle({ id: "5", type: "set_meta", conversationId: ids[2] as number, state: "deleted" });
	await gateway.handle({ id: "6", type: "set_meta", conversationId: ids[0] as number, name: "Named" });
	await gateway.handle({ id: "7", type: "list_conversations" });

	// Assert
	const conversations = (reply(outgoing, "7") as Listed).result.conversations;
	const byId = Object.fromEntries(conversations.map((c) => [c.id, [c.state, c.name]]));
	assert.deepEqual(byId, { [ids[0] as number]: ["active", "Named"], [ids[1] as number]: ["archived", null] });
	await close();
});

test("set_meta rejects an unknown state and an empty name clears the name", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();
	await gateway.handle({ id: "1", type: "create_conversation", name: "Old" });
	const id = (reply(outgoing, "1") as { result: { conversationId: number } }).result.conversationId;

	// Act
	await gateway.handle({ id: "2", type: "set_meta", conversationId: id, state: "bogus" as never });
	await gateway.handle({ id: "3", type: "set_meta", conversationId: id, name: "  " });
	await gateway.handle({ id: "4", type: "list_conversations" });

	// Assert
	assert.equal((reply(outgoing, "2") as { ok: boolean }).ok, false);
	assert.equal((reply(outgoing, "4") as Listed).result.conversations[0]?.name, null);
	await close();
});

test("list_models returns the configured model and the endpoint's models", async () => {
	// Arrange
	const { close, gateway, outgoing } = await setup();

	// Act
	await gateway.handle({ id: "1", type: "list_models" });

	// Assert
	const listed = reply(outgoing, "1") as { result: { current: { modelId: string }; models: string[] } };
	assert.deepEqual(listed.result.models, ["alpha", "beta"]);
	assert.equal(typeof listed.result.current.modelId, "string");
	await close();
});
