import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { Models } from "@earendil-works/pi-ai";
import {
	createRegistry,
	defineExtension,
	Harness,
	type PromptInput,
	section,
	type Storage,
} from "@earendil-works/pi-durable";
import { NodeExecutionEnv } from "@earendil-works/pi-durable/env/node";
import { CodingTools } from "@earendil-works/pi-durable/tools";
import { CodemodeExtension } from "./codemode.ts";
import { discoverInstructions, renderInstructions } from "./project-instructions.ts";
import { discoverSkills, renderSkills } from "./skills.ts";

function frozenSection(key: string, render: (input: PromptInput) => Promise<string | undefined>) {
	return section(key, async (input) => input.shown[key] ?? (await render(input)), { tag: false });
}

function environment(configDir: string) {
	return defineExtension({
		name: "environment",
		sections: [
			section("cwd", (input) => input.env?.cwd),
			frozenSection("project_instructions", async (input) =>
				input.env ? renderInstructions(await discoverInstructions(input.env.cwd, configDir)) : undefined,
			),
			frozenSection("skills", async (input) => {
				const canRead = input.agent.tools.some((tool) => tool.name === "read");
				if (!input.env || !canRead) return undefined;
				return renderSkills((await discoverSkills(input.env.cwd, configDir)).skills);
			}),
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
