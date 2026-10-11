import assert from "node:assert/strict";
import { access, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import type { Policy } from "../src/permissions/rules.ts";
import type { Outgoing } from "../src/protocol.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;
type Message = { role: string; content: unknown };

const ASK: Policy = { mode: "ask", allow: [], ask: [], deny: [] };

function requests(outgoing: Outgoing[]) {
	return outgoing.filter((message) => message.type === "permission_request");
}

async function exists(path: string) {
	return access(path).then(
		() => true,
		() => false,
	);
}

async function create(harness: Harness, id: string, persona?: string) {
	await harness.gateway.handle({ id, type: "create_conversation", cwd: tmpdir(), ...(persona ? { persona } : {}) });
	const { conversationId } = (reply(harness.outgoing, id) as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: `attach-${id}`, type: "attach", conversationId });
	return conversationId;
}

async function setMode(harness: Harness, conversationId: number, mode?: string) {
	await harness.gateway.handle({ id: `m${Math.random()}`, type: "permission_mode", conversationId, mode } as never);
	const last = harness.outgoing[harness.outgoing.length - 1] as { ok: boolean; result?: { mode: string; default: string }; error?: string };
	return last;
}

async function runBash(harness: Harness, conversationId: number, marker: string) {
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${marker}` }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);
	const before = harness.outgoing.filter((message) => JSON.stringify(message).includes("run_end")).length;
	await harness.gateway.handle({ id: `s${Math.random()}`, type: "submit", conversationId, content: "go" });
	return before;
}

test("a session's mode is reported, can be changed, and leaves other sessions and the default alone", async () => {
	// Arrange
	const harness = await setup(ASK);
	const first = await create(harness, "a");
	const second = await create(harness, "b");

	// Act
	const initial = await setMode(harness, first);
	const changed = await setMode(harness, first, "auto");
	const other = await setMode(harness, second);
	const invalid = await setMode(harness, first, "yolo");

	// Assert
	assert.deepEqual([initial.result?.mode, initial.result?.default], ["ask", "ask"]);
	assert.equal(changed.result?.mode, "auto");
	assert.equal(other.result?.mode, "ask");
	assert.equal(invalid.ok, false);
	assert.equal((await setMode(harness, first)).result?.mode, "auto");
	await harness.close();
});

test("auto mode runs a call without asking in that session while another session still asks", async () => {
	// Arrange
	const harness = await setup(ASK);
	const dir = await mkdtemp(join(tmpdir(), "sak-mode-"));
	const auto = await create(harness, "a");
	const asking = await create(harness, "b");
	await setMode(harness, auto, "auto");

	// Act
	const first = await runBash(harness, auto, join(dir, "auto"));
	await waitFor(() => harness.outgoing.filter((m) => JSON.stringify(m).includes("run_end")).length > first);
	const second = await runBash(harness, asking, join(dir, "asked"));
	await waitFor(() => requests(harness.outgoing).length === 1);

	// Assert
	assert.equal(await exists(join(dir, "auto")), true);
	assert.equal(await exists(join(dir, "asked")), false);
	assert.equal(second >= 0, true);
	await harness.close();
});

test("the mode of the root session applies to its subagents, except for tools their persona does not have", async () => {
	// Arrange
	const harness = await setup(ASK, 6);
	await writeFile(join(harness.personasDir, "reader.md"), "---\nname: reader\ntools: Read\n---\nOnly read.");
	const dir = await mkdtemp(join(tmpdir(), "sak-mode-"));
	const root = await create(harness, "a");
	await setMode(harness, root, "auto");
	const touch = (name: string) => fauxToolCall("bash", { command: `touch ${join(dir, name)}` });
	const child = (name: string) => (context: { messages: Message[] }) => {
		const last = context.messages[context.messages.length - 1];
		if (last?.role === "toolResult") return fauxAssistantMessage("child done");
		return fauxAssistantMessage(touch(name), { stopReason: "toolUse" });
	};
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("agent", { prompts: ["do it"] }), { stopReason: "toolUse" }),
		child("full"),
		child("full"),
		fauxAssistantMessage(fauxToolCall("agent", { prompts: ["do it"], persona: "reader" }), { stopReason: "toolUse" }),
		child("limited"),
		child("limited"),
		fauxAssistantMessage("finished"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId: root, content: "go" });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(await exists(join(dir, "full")), true);
	assert.equal(await exists(join(dir, "limited")), false);
	assert.equal(requests(harness.outgoing).length, 0);
	await harness.close();
});

test("a deny rule still wins in auto mode", async () => {
	// Arrange
	const harness = await setup({ ...ASK, deny: [{ tool: "bash", pattern: "touch *" }] });
	const dir = await mkdtemp(join(tmpdir(), "sak-mode-"));
	const id = await create(harness, "a");
	await setMode(harness, id, "auto");

	// Act
	const before = await runBash(harness, id, join(dir, "x"));
	await waitFor(() => harness.outgoing.filter((m) => JSON.stringify(m).includes("run_end")).length > before);

	// Assert
	assert.equal(await exists(join(dir, "x")), false);
	assert.match(JSON.stringify(harness.outgoing), /Permission denied by a rule/);
	await harness.close();
});
