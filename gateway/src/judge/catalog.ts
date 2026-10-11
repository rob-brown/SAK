import { Type } from "@earendil-works/pi-ai";
import { defineTool } from "@earendil-works/pi-durable";

export const JUDGE = "judge";

export const DESCRIPTION = [
	"Ask a small decision model typed questions about some text or data. It does not write text; it returns calibrated answers you can branch on.",
	"state is the text or data the questions are about (JSON text for structured data). questions maps your own ids to questions; answers come back under the same ids.",
	'Each question has a type and instructions. type "choice": criteria is an object mapping each option to its meaning (include an "other" option); the answer has the chosen option, its confidence and the probability of every option.',
	'type "noul": a yes/no condition, optionally with criteria {"true": ..., "false": ...}; the answer is the probability of yes from 0 to 1, where near 0.5 means uncertain.',
	'type "score": criteria is a list of 2 to 10 level descriptions from lowest to highest; the answer is a position along that scale with a confidence.',
	"Keep each question narrow and independent, and put everything the model needs to answer in state or instructions.",
].join("\n");

export const PARAMETERS = Type.Object({
	state: Type.String({ description: "Text, or JSON text for structured data, that the questions are about" }),
	questions: Type.Record(
		Type.String(),
		Type.Object({
			type: Type.Unsafe<"choice" | "noul" | "score">({ type: "string", enum: ["choice", "noul", "score"] }),
			instructions: Type.String(),
			criteria: Type.Optional(Type.Any({ description: "Options, levels or yes/no meanings; see the tool description" })),
		}),
		{ minProperties: 1 },
	),
});

export const JudgeCatalogEntry = defineTool({
	name: JUDGE,
	description: DESCRIPTION,
	parameters: PARAMETERS,
	execute: async () => ({ content: [{ type: "text", text: "judge is not enabled" }], isError: true }),
});
