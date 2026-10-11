import { createInterface } from "node:readline";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { listEndpointModels } from "./endpoint.ts";
import { loadConfig } from "./config.ts";
import { Gateway } from "./gateway.ts";
import { ModelCatalog, PROVIDER_ID } from "./models.ts";
import { JudgeClient } from "./judge/client.ts";
import { openHarness } from "./open.ts";
import { Authorizer } from "./permissions/authorizer.ts";
import { PermissionBroker } from "./permissions/broker.ts";
import { PermissionJudge } from "./permissions/judge.ts";
import { type HarnessRef, personaRulesFor } from "./permissions/persona-rules.ts";
import { rootConversation } from "./permissions/root.ts";
import type { Command, Outgoing } from "./protocol.ts";
import { Semaphore } from "./subagents/semaphore.ts";

const config = await loadConfig(process.env).catch((error: unknown) => {
	process.stderr.write(`sak: ${error instanceof Error ? error.message : String(error)}\n`);
	return process.exit(2);
});
for (const warning of config.warnings) process.stderr.write(`sak: ${warning}\n`);
const storage = await openNodeSqliteStorage(config.dbPath);
const catalog = new ModelCatalog(config);

const send = (message: Outgoing) => {
	process.stdout.write(`${JSON.stringify(message)}\n`);
};

const judge = config.judge.enabled ? new JudgeClient(config.judge) : undefined;
const internal = judge ? { client: judge, minConfidence: config.judge.minConfidence } : undefined;

const needsJudge = (config.permissions.judge ?? []).length > 0;
if (needsJudge && !judge) {
	process.stderr.write("sak: [permissions] judge rules need [judge] enabled = true; those calls will ask a person\n");
}
const permissionJudge =
	judge && needsJudge
		? new PermissionJudge(
				new JudgeClient({ ...config.judge, model: config.judge.permissionModel ?? config.judge.model }),
				config.permissionThreshold,
			)
		: undefined;

const broker = new PermissionBroker(send);
const live: HarnessRef = {};
const personaRules = personaRulesFor(config.personasDir, live);
const authorizer = new Authorizer(config.permissions, broker, rootConversation(storage), permissionJudge, personaRules);
const harness = await openHarness(storage, catalog.models, {
	authorizer,
	configDir: config.configDir,
	instructionMaxChars: config.instructionMaxChars,
	...(judge ? { judge } : {}),
	subagents: {
		personasDir: config.personasDir,
		semaphore: new Semaphore(config.subagentLimit),
		...(internal && config.judge.pickPersonas ? { judge: internal } : {}),
	},
});

live.harness = harness;

const gateway = new Gateway({
	authorizer,
	broker,
	cwd: config.cwd,
	ensureModel: (modelId) => catalog.ensure(modelId),
	harness,
	listModels: () => listEndpointModels(config.baseUrl, config.apiKey),
	model: { provider: PROVIDER_ID, modelId: config.modelId },
	personasDir: config.personasDir,
	send,
	storage,
	...(internal && config.judge.suggestSkills ? { suggestions: { ...internal, configDir: config.configDir } } : {}),
});

const lines = createInterface({ input: process.stdin });
let queue: Promise<void> = Promise.resolve();

lines.on("line", (line) => {
	if (line.trim() === "") return;
	const command = parse(line);
	if (command === undefined) return;
	queue = queue.then(() => gateway.handle(command));
});

lines.on("close", async () => {
	await queue;
	await gateway.close();
	await harness.close(BACKGROUND_CONTEXT);
	process.exit(0);
});

function parse(line: string): Command | undefined {
	try {
		return JSON.parse(line) as Command;
	} catch {
		send({ type: "reply", id: null, ok: false, error: "invalid JSON" });
		return undefined;
	}
}
