import assert from "node:assert/strict";
import { access, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { BACKGROUND_CONTEXT, withCancel } from "@earendil-works/chord/context";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { Authorizer } from "../src/permissions/authorizer.ts";
import { PermissionBroker } from "../src/permissions/broker.ts";
import { type Mode, parseRule, type Policy } from "../src/permissions/rules.ts";
import type { Outgoing } from "../src/protocol.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Request = Extract<Outgoing, { type: "permission_request" }>;

function policy(mode: Mode, deny: string[] = []): Policy {
	return { mode, allow: [], ask: [], deny: deny.map(parseRule) };
}

function requests(outgoing: Outgoing[]): Request[] {
	return outgoing.filter((message): message is Request => message.type === "permission_request");
}

async function exists(path: string) {
	return access(path).then(
		() => true,
		() => false,
	);
}

async function session(harness: Awaited<ReturnType<typeof setup>>, responses: Parameters<typeof harness.faux.setResponses>[0]) {
	const { faux, gateway, outgoing } = harness;
	faux.setResponses(responses);
	await gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir() });
	const { conversationId } = (reply(outgoing, "c") as { result: { conversationId: number } }).result;
	await gateway.handle({ id: "a", type: "attach", conversationId });
	return conversationId;
}

async function answer(harness: Awaited<ReturnType<typeof setup>>, approval: "allow" | "allow_conversation" | "deny", count = 1) {
	await waitFor(() => requests(harness.outgoing).length >= count);
	const request = requests(harness.outgoing)[count - 1] as Request;
	await harness.gateway.handle({ id: `r${count}`, type: "permission_reply", requestId: request.requestId, approval });
}

test("a bash call waits for approval, runs once allowed, and the request is announced as resolved", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const marker = join(await mkdtemp(join(tmpdir(), "sak-perm-")), "ran");
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${marker}` }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => requests(harness.outgoing).length === 1);
	const before = await exists(marker);
	await answer(harness, "allow");
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(before, false);
	assert.equal(await exists(marker), true);
	assert.equal(requests(harness.outgoing)[0]?.summary, `touch ${marker}`);
	assert.ok(harness.outgoing.some((m) => m.type === "permission_resolved"));
	await harness.close();
});

test("a denied call never runs and the model is told why", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const marker = join(await mkdtemp(join(tmpdir(), "sak-perm-")), "ran");
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${marker}` }), { stopReason: "toolUse" }),
		fauxAssistantMessage("understood"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await answer(harness, "deny");
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(await exists(marker), false);
	assert.match(JSON.stringify(harness.outgoing), /Permission denied by the user/);
	await harness.close();
});

test("a deny rule blocks without asking, and auto mode runs everything else without asking", async () => {
	// Arrange
	const harness = await setup(policy("auto", ["Bash(rm *)"]));
	const dir = await mkdtemp(join(tmpdir(), "sak-perm-"));
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("bash", { command: `rm -rf ${dir}` }), { stopReason: "toolUse" }),
		fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${dir}/ok` }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(requests(harness.outgoing).length, 0);
	assert.match(JSON.stringify(harness.outgoing), /Permission denied by a rule/);
	assert.equal(await exists(join(dir, "ok")), true);
	await harness.close();
});

test("tools called from a codemode script are checked too", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const marker = join(await mkdtemp(join(tmpdir(), "sak-perm-")), "ran");
	const code = `await tools.bash({ command: "touch ${marker}" });`;
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("codemode", { code }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await answer(harness, "deny");
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(requests(harness.outgoing)[0]?.tool, "bash");
	assert.equal(await exists(marker), false);
	assert.match(JSON.stringify(harness.outgoing), /Script failed/);
	await harness.close();
});

test("allowing for the conversation skips the question for the same command but not for others", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const dir = await mkdtemp(join(tmpdir(), "sak-perm-"));
	const same = { command: `touch ${dir}/a` };
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("bash", same), { stopReason: "toolUse" }),
		fauxAssistantMessage(fauxToolCall("bash", same), { stopReason: "toolUse" }),
		fauxAssistantMessage(fauxToolCall("bash", { command: `touch ${dir}/b` }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);

	// Act
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await answer(harness, "allow_conversation", 1);
	await answer(harness, "allow", 2);
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.equal(requests(harness.outgoing).length, 2);
	assert.deepEqual(
		requests(harness.outgoing).map((request) => request.summary),
		[`touch ${dir}/a`, `touch ${dir}/b`],
	);
	await harness.close();
});

test("a pending request is sent again when the conversation is attached again", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const conversationId = await session(harness, [
		fauxAssistantMessage(fauxToolCall("bash", { command: "echo hi" }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => requests(harness.outgoing).length === 1);

	// Act
	await harness.gateway.handle({ id: "again", type: "attach", conversationId });

	// Assert
	const sent = requests(harness.outgoing);
	assert.equal(sent.length, 2);
	assert.equal(sent[0]?.requestId, sent[1]?.requestId);
	await answer(harness, "deny");
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	await harness.close();
});

test("cancelling the waiting call withdraws the request, and replying to an unknown request is harmless", async () => {
	// Arrange
	const outgoing: Outgoing[] = [];
	const broker = new PermissionBroker((message) => outgoing.push(message));
	const authorizer = new Authorizer(policy("ask"), broker);
	const { context, cancel } = withCancel(BACKGROUND_CONTEXT);

	// Act
	const waiting = authorizer.authorize({ name: "bash", arguments: { command: "make" } }, { conversationId: 1, cwd: "/x" }, context);
	cancel(new Error("aborted"));
	await assert.rejects(waiting, /aborted/);

	// Assert
	assert.deepEqual(
		outgoing.map((message) => message.type),
		["permission_request", "permission_resolved"],
	);
	assert.equal(broker.pending(1).length, 0);
	assert.equal(broker.reply("missing", "allow"), false);
});
