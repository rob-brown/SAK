import assert from "node:assert/strict";
import { test } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai/models";
import { fauxAssistantMessage, fauxProvider } from "@earendil-works/pi-ai/providers/faux";
import { MemoryStorage } from "@earendil-works/pi-durable/storage/memory";
import { Gateway } from "../src/gateway.ts";
import { openHarness } from "../src/open.ts";
import type { Command, Outgoing } from "../src/protocol.ts";

async function setup() {
	const faux = fauxProvider();
	const models = createModels();
	models.setProvider(faux.provider);
	const storage = new MemoryStorage();
	const harness = await openHarness(storage, models);
	const outgoing: Outgoing[] = [];
	const model = faux.getModel();
	const gateway = new Gateway({
		cwd: process.cwd(),
		harness,
		model: { provider: model.provider, modelId: model.id },
		send: (message) => outgoing.push(message),
		storage,
	});
	const close = async () => {
		await gateway.close();
		await harness.close(BACKGROUND_CONTEXT);
	};
	return { close, faux, gateway, outgoing };
}

async function waitFor(condition: () => boolean) {
	const deadline = Date.now() + 5000;
	while (!condition()) {
		if (Date.now() > deadline) throw new Error("timed out");
		await new Promise((resolve) => setTimeout(resolve, 10));
	}
}

function reply(outgoing: Outgoing[], id: string) {
	return outgoing.find((message) => message.type === "reply" && message.id === id);
}

function hasEvent(outgoing: Outgoing[], type: string) {
	return outgoing.some(
		(message) =>
			message.type === "events" &&
			(message.events as { type: string }[]).some((event) => event.type === type),
	);
}

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
