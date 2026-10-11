import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai/models";
import { fauxProvider } from "@earendil-works/pi-ai/providers/faux";
import { MemoryStorage } from "@earendil-works/pi-durable/storage/memory";
import { Gateway } from "../src/gateway.ts";
import type { JudgeClient } from "../src/judge/client.ts";
import { openHarness } from "../src/open.ts";
import { Authorizer } from "../src/permissions/authorizer.ts";
import { PermissionBroker } from "../src/permissions/broker.ts";
import { rootConversation } from "../src/permissions/root.ts";
import type { Policy } from "../src/permissions/rules.ts";
import type { Outgoing } from "../src/protocol.ts";
import { Semaphore } from "../src/subagents/semaphore.ts";

export async function setup(policy?: Policy, subagentLimit?: number, judge?: JudgeClient) {
	const faux = fauxProvider();
	const models = createModels();
	models.setProvider(faux.provider);
	const storage = new MemoryStorage();
	const personasDir = await mkdtemp(join(tmpdir(), "sak-personas-"));
	const configDir = await mkdtemp(join(tmpdir(), "sak-config-"));
	const outgoing: Outgoing[] = [];
	const send = (message: Outgoing) => outgoing.push(message);
	const broker = policy ? new PermissionBroker(send) : undefined;
	const authorizer = policy && broker ? new Authorizer(policy, broker, rootConversation(storage)) : undefined;
	const subagents = subagentLimit ? { personasDir, semaphore: new Semaphore(subagentLimit) } : undefined;
	const harness = await openHarness(storage, models, {
		configDir,
		...(authorizer ? { authorizer } : {}),
		...(subagents ? { subagents } : {}),
		...(judge ? { judge } : {}),
	});
	const ensured: string[] = [];
	const model = faux.getModel();
	const gateway = new Gateway({
		...(authorizer ? { authorizer } : {}),
		...(broker ? { broker } : {}),
		cwd: process.cwd(),
		personasDir,
		ensureModel: async (modelId) => {
			ensured.push(modelId);
		},
		harness,
		listModels: async () => ["alpha", "beta"],
		model: { provider: model.provider, modelId: model.id },
		send,
		storage,
	});
	const close = async () => {
		await gateway.close();
		await harness.close(BACKGROUND_CONTEXT);
	};
	return { close, configDir, ensured, faux, gateway, outgoing, personasDir };
}

export async function waitFor(condition: () => boolean) {
	const deadline = Date.now() + 5000;
	while (!condition()) {
		if (Date.now() > deadline) throw new Error("timed out");
		await new Promise((resolve) => setTimeout(resolve, 10));
	}
}

export function reply(outgoing: Outgoing[], id: string) {
	return outgoing.find((message) => message.type === "reply" && message.id === id);
}

export function hasEvent(outgoing: Outgoing[], type: string) {
	return outgoing.some(
		(message) =>
			message.type === "events" && (message.events as { type: string }[]).some((event) => event.type === type),
	);
}
