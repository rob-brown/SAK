import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { Models } from "@earendil-works/pi-ai";
import { createRegistry, defineExtension, Harness, section, type Storage } from "@earendil-works/pi-durable";
import { NodeExecutionEnv } from "@earendil-works/pi-durable/env/node";
import { CodingTools } from "@earendil-works/pi-durable/tools";
import { CodemodeExtension } from "./codemode.ts";
import { discoverInstructions, renderInstructions } from "./project-instructions.ts";

function environment(configDir: string) {
	return defineExtension({
		name: "environment",
		sections: [
			section("cwd", (input) => input.env?.cwd),
			section(
				"project_instructions",
				async (input) => {
					const loaded = input.shown.project_instructions;
					if (loaded !== undefined) return loaded;
					return input.env ? renderInstructions(await discoverInstructions(input.env.cwd, configDir)) : undefined;
				},
				{ tag: false },
			),
		],
	});
}

export async function openHarness(storage: Storage, models: Models, configDir: string) {
	const registry = createRegistry();
	registry.install(CodingTools);
	registry.install(CodemodeExtension);
	registry.install(environment(configDir));
	const harness = await Harness.open(
		storage,
		{ models, registry, env: ({ cwd }) => new NodeExecutionEnv({ cwd: cwd ?? process.cwd() }) },
		BACKGROUND_CONTEXT,
	);
	harness.resume();
	return harness;
}
