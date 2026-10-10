import { createInterface } from "node:readline";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { listEndpointModels } from "./endpoint.ts";
import { loadConfig } from "./config.ts";
import { Gateway } from "./gateway.ts";
import { ModelCatalog, PROVIDER_ID } from "./models.ts";
import { openHarness } from "./open.ts";
import type { Command, Outgoing } from "./protocol.ts";

const config = loadConfig(process.env);
const storage = await openNodeSqliteStorage(config.dbPath);
const catalog = new ModelCatalog(config);
const harness = await openHarness(storage, catalog.models);

const send = (message: Outgoing) => {
	process.stdout.write(`${JSON.stringify(message)}\n`);
};

const gateway = new Gateway({
	cwd: config.cwd,
	ensureModel: (modelId) => catalog.ensure(modelId),
	harness,
	listModels: () => listEndpointModels(config.baseUrl, config.apiKey),
	model: { provider: PROVIDER_ID, modelId: config.modelId },
	personasDir: config.personasDir,
	send,
	storage,
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
