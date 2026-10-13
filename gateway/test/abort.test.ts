import assert from "node:assert/strict";
import { access, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import type { Mode, Policy } from "../src/permissions/rules.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;

function policy(mode: Mode): Policy {
	return { mode, allow: [], ask: [], deny: [] };
}

async function exists(path: string) {
	return access(path).then(
		() => true,
		() => false,
	);
}

async function session(harness: Harness, responses: Parameters<Harness["faux"]["setResponses"]>[0]) {
	harness.faux.setResponses(responses);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir() });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	return conversationId;
}

function bash(command: string) {
	return fauxAssistantMessage(fauxToolCall("bash", { command }), { stopReason: "toolUse" });
}

test("abort kills a running bash command, records the tool as aborted, and ends the run without another model call", async () => {
	// Arrange
	const harness = await setup(policy("auto"));
	const marker = join(await mkdtemp(join(tmpdir(), "sak-abort-")), "ran");
	const conversationId = await session(harness, [bash(`sleep 2; touch ${marker}`), fauxAssistantMessage("never sent")]);
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => JSON.stringify(harness.outgoing).includes("tool_execution_start"));

	// Act
	await harness.gateway.handle({ id: "x", type: "abort", conversationId });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	await new Promise((resolve) => setTimeout(resolve, 2500));

	// Assert
	assert.equal(await exists(marker), false);
	assert.match(JSON.stringify(harness.outgoing), /Tool bash was aborted/);
	assert.equal(harness.faux.getPendingResponseCount(), 1);
	await harness.close();
});

test("abort while a permission prompt is pending resolves the prompt and the tool never runs", async () => {
	// Arrange
	const harness = await setup(policy("ask"));
	const marker = join(await mkdtemp(join(tmpdir(), "sak-abort-")), "ran");
	const conversationId = await session(harness, [bash(`touch ${marker}`), fauxAssistantMessage("never sent")]);
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => harness.outgoing.some((m) => m.type === "permission_request"));

	// Act
	await harness.gateway.handle({ id: "x", type: "abort", conversationId });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));

	// Assert
	assert.ok(harness.outgoing.some((m) => m.type === "permission_resolved"));
	assert.equal(await exists(marker), false);
	assert.equal(harness.faux.getPendingResponseCount(), 1);
	await harness.close();
});

test("after an abort the conversation accepts a new submission and completes it", async () => {
	// Arrange
	const harness = await setup(policy("auto"));
	const conversationId = await session(harness, [bash("sleep 30"), fauxAssistantMessage("recovered")]);
	await harness.gateway.handle({ id: "s1", type: "submit", conversationId, content: "first" });
	await waitFor(() => JSON.stringify(harness.outgoing).includes("tool_execution_start"));
	await harness.gateway.handle({ id: "x", type: "abort", conversationId });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	const endsBefore = JSON.stringify(harness.outgoing).split('"type":"run_end"').length;

	// Act
	await harness.gateway.handle({ id: "s2", type: "submit", conversationId, content: "second" });
	await waitFor(() => JSON.stringify(harness.outgoing).split('"type":"run_end"').length > endsBefore);

	// Assert
	assert.match(JSON.stringify(harness.outgoing), /recovered/);
	await harness.close();
});

test("abort on an idle conversation succeeds and changes nothing", async () => {
	// Arrange
	const harness = await setup();
	await harness.gateway.handle({ id: "c", type: "create_conversation" });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;

	// Act
	await harness.gateway.handle({ id: "x", type: "abort", conversationId });

	// Assert
	assert.deepEqual(reply(harness.outgoing, "x"), { type: "reply", id: "x", ok: true, result: {} });
	assert.equal(hasEvent(harness.outgoing, "run_start"), false);
	await harness.close();
});

test("abort for an unknown conversation replies with an error", async () => {
	// Arrange
	const harness = await setup();

	// Act
	await harness.gateway.handle({ id: "x", type: "abort", conversationId: 9999 });

	// Assert
	assert.deepEqual(reply(harness.outgoing, "x"), { type: "reply", id: "x", ok: false, error: "unknown conversation 9999" });
	await harness.close();
});
