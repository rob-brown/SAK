import { Type } from "@earendil-works/pi-ai";
import { defineTool } from "@earendil-works/pi-durable";

export const AGENT = "agent";
export const MAX_PROMPTS = 200;

export const DESCRIPTION = [
	"Delegate self-contained tasks to subagents. Each prompt runs in its own fresh conversation, which sees none of this one, so include everything it needs.",
	"A limited number of subagents run at once and the rest wait their turn.",
	"Returns a JSON array of strings, one answer per prompt in the same order; a prompt that failed gives a string starting with 'Error:'.",
	"Optional persona applies to every subagent in this call. Leave it out and a fitting persona may be chosen for each prompt, falling back to the default.",
].join("\n");

export const PARAMETERS = Type.Object({
	prompts: Type.Array(Type.String({ minLength: 1 }), { minItems: 1, maxItems: MAX_PROMPTS }),
	persona: Type.Optional(Type.String({ description: "Persona name; defaults to the default persona" })),
});

export const AgentCatalogEntry = defineTool({
	name: AGENT,
	description: DESCRIPTION,
	parameters: PARAMETERS,
	execute: async () => ({ content: [{ type: "text", text: "agent is not available here" }], isError: true }),
});
