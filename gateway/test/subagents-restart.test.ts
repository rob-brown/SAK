import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai/models";
import { fauxAssistantMessage, fauxProvider, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { MemoryStorage } from "@earendil-works/pi-durable/storage/memory";
import { openHarness } from "../src/open.ts";
import { Semaphore } from "../src/subagents/semaphore.ts";
import { waitFor } from "./support.ts";

type Message = { role: string; content: unknown };

function lastUserText(messages: Message[]): string {
	const user = [...messages].reverse().find((message) => message.role === "user");
	return typeof user?.content === "string" ? user.content : "";
}

async function boot(storage: MemoryStorage, faux: ReturnType<typeof fauxProvider>, directory: string) {
	const models = createModels();
	models.setProvider(faux.provider);
	return openHarness(storage, models, {
		configDir: directory,
		subagents: { personasDir: directory, semaphore: new Semaphore(6) },
	});
}

test("after a restart the unfinished subagent is picked up again and finished ones are not run twice", async () => {
	// Arrange
	const directory = await mkdtemp(join(tmpdir(), "sak-restart-"));
	const storage = new MemoryStorage();
	const first = fauxProvider();
	const ran: string[] = [];
	const stuck = new Promise<never>(() => {});
	const answer = (context: { messages: Message[] }) => {
		const prompt = lastUserText(context.messages);
		ran.push(prompt);
		return prompt === "slow" ? stuck : Promise.resolve(fauxAssistantMessage(`echo:${prompt}`));
	};
	first.setResponses([
		fauxAssistantMessage(fauxToolCall("agent", { prompts: ["fast", "slow"] }), { stopReason: "toolUse" }),
		answer,
		answer,
	]);
	const harnessOne = await boot(storage, first, directory);
	const model = first.getModel();
	const root = await harnessOne.createConversation(
		{ ownership: { kind: "ownerless" }, agent: { model: { provider: model.provider, modelId: model.id } } },
		BACKGROUND_CONTEXT,
	);
	await root.submit({ type: "input", content: "go" }, BACKGROUND_CONTEXT);
	await waitFor(() => ran.includes("fast") && ran.includes("slow"));

	// Act
	const closing = harnessOne.close(BACKGROUND_CONTEXT).catch(() => undefined);
	await Promise.race([closing, new Promise((resolve) => setTimeout(resolve, 2000))]);
	const second = fauxProvider();
	const rerun: string[] = [];
	second.setResponses([
		(context: { messages: Message[] }) => {
			rerun.push(lastUserText(context.messages));
			return fauxAssistantMessage(`echo:${lastUserText(context.messages)}`);
		},
		fauxAssistantMessage("all done"),
	]);
	const harnessTwo = await boot(storage, second, directory);
	const reopened = await harnessTwo.conversation(root.id, BACKGROUND_CONTEXT);
	await reopened?.waitForIdle?.(BACKGROUND_CONTEXT);

	const entries = (await reopened?.entries({}, 100, undefined, BACKGROUND_CONTEXT))?.items;

	// Assert
	assert.deepEqual(rerun, ["slow"]);
	const transcript = JSON.stringify(entries);
	assert.match(transcript, /echo:fast/);
	assert.match(transcript, /echo:slow/);
	assert.match(transcript, /all done/);
	await harnessTwo.close(BACKGROUND_CONTEXT);
});
