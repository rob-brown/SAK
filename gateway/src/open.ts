import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { Models } from "@earendil-works/pi-ai";
import { createRegistry, defineExtension, Harness, section, type Storage } from "@earendil-works/pi-durable";
import { NodeExecutionEnv } from "@earendil-works/pi-durable/env/node";
import { CodingTools } from "@earendil-works/pi-durable/tools";
import { CodemodeExtension } from "./codemode.ts";

const Environment = defineExtension({
	name: "environment",
	sections: [section("cwd", (input) => input.env?.cwd)],
});

export async function openHarness(storage: Storage, models: Models) {
	const registry = createRegistry();
	registry.install(CodingTools);
	registry.install(CodemodeExtension);
	registry.install(Environment);
	const harness = await Harness.open(
		storage,
		{ models, registry, env: ({ cwd }) => new NodeExecutionEnv({ cwd: cwd ?? process.cwd() }) },
		BACKGROUND_CONTEXT,
	);
	harness.resume();
	return harness;
}
