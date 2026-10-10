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
	const ensured: string[] = [];
	const model = faux.getModel();
	const gateway = new Gateway({
		cwd: process.cwd(),
		ensureModel: async (modelId) => {
			ensured.push(modelId);
		},
		harness,
		listModels: async () => ["alpha", "beta"],
		model: { provider: model.provider, modelId: model.id },
		send: (message) => outgoing.push(message),
		storage,
	});
	const close = async () => {
		await gateway.close();
		await harness.close(BACKGROUND_CONTEXT);
	};
	return { close, ensured, faux, gateway, outgoing };
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

type Listed = { result: { conversations: { id: number; name: string | null; state: string; model: string }[] } };

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
