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
import type { Authorizer } from "./permissions/authorizer.ts";
import { permissionsExtension } from "./permissions/extension.ts";
import { discoverInstructions, renderInstructions } from "./project-instructions.ts";
import { discoverSkills, renderSkills } from "./skills.ts";
import { type SubagentDeps, subagentExtension } from "./subagents/tool.ts";

function frozenSection(key: string, render: (input: PromptInput) => Promise<string | undefined>) {
	return section(key, async (input) => input.shown[key] ?? (await render(input)), { tag: false });
}

export type OpenOptions = {
	readonly authorizer?: Authorizer;
	readonly configDir: string;
	readonly instructionMaxChars?: number;
	readonly subagents?: SubagentDeps;
};

function environment({ configDir, instructionMaxChars }: OpenOptions) {
	return defineExtension({
		name: "environment",
		sections: [
			section("cwd", (input) => input.env?.cwd),
			frozenSection("project_instructions", async (input) =>
				input.env
					? renderInstructions(await discoverInstructions(input.env.cwd, configDir, instructionMaxChars))
					: undefined,
			),
			frozenSection("skills", async (input) => {
				const canRead = input.agent.tools.some((tool) => tool.name === "read");
				if (!input.env || !canRead) return undefined;
				return renderSkills((await discoverSkills(input.env.cwd, configDir)).skills);
			}),
		],
	});
}

export async function openHarness(storage: Storage, models: Models, options: OpenOptions) {
	const registry = createRegistry();
	registry.install(CodingTools);
	registry.install(CodemodeExtension);
	registry.install(environment(options));
	if (options.subagents) registry.install(subagentExtension(options.subagents));
	if (options.authorizer) registry.install(permissionsExtension(options.authorizer));
	const harness = await Harness.open(
		storage,
		{ models, registry, env: ({ cwd }) => new NodeExecutionEnv({ cwd: cwd ?? process.cwd() }) },
		BACKGROUND_CONTEXT,
	);
	harness.resume();
	return harness;
}
