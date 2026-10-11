import { defineExtension, defineTool } from "@earendil-works/pi-durable";
import { DESCRIPTION, JUDGE, PARAMETERS } from "./catalog.ts";
import type { JudgeClient, JudgeQuestion } from "./client.ts";

const MIN_LEVELS = 2;
const MAX_LEVELS = 10;
const MAX_OPTIONS = 255;

export function judgeExtension(client: JudgeClient) {
	const tool = defineTool({
		name: JUDGE,
		description: DESCRIPTION,
		parameters: PARAMETERS,
		replay: "safe",
		execute: async (args, _api, context) => {
			const problem = validate(args.questions);
			if (problem !== undefined) return { content: [{ type: "text", text: problem }], isError: true };
			try {
				const { answers } = await client.evaluate(structured(args.state), args.questions, context.abortSignal);
				return { content: [{ type: "text", text: JSON.stringify(answers) }] };
			} catch (error) {
				if (context.abortSignal?.aborted) throw error;
				const message = error instanceof Error ? error.message : String(error);
				return { content: [{ type: "text", text: message }], isError: true };
			}
		},
	});
	return defineExtension({ name: "judge", tools: [tool] });
}

export function validate(questions: Readonly<Record<string, JudgeQuestion>>): string | undefined {
	for (const [id, question] of Object.entries(questions)) {
		const problem = check(question);
		if (problem !== undefined) return `question "${id}": ${problem}`;
	}
	return undefined;
}

function check({ type, criteria }: JudgeQuestion): string | undefined {
	if (type === "choice") {
		const options = isRecord(criteria) ? Object.keys(criteria).length : 0;
		if (options < 2 || options > MAX_OPTIONS) return `a choice needs criteria mapping 2 to ${MAX_OPTIONS} options to their meaning`;
	}
	if (type === "score") {
		const levels = Array.isArray(criteria) ? criteria.length : 0;
		if (levels < MIN_LEVELS || levels > MAX_LEVELS) return `a score needs criteria listing ${MIN_LEVELS} to ${MAX_LEVELS} levels`;
	}
	if (type === "noul" && criteria !== undefined && !isRecord(criteria)) {
		return 'a noul takes criteria as an object like {"true": "...", "false": "..."}, or none';
	}
	return undefined;
}

function structured(state: string): unknown {
	const trimmed = state.trim();
	if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return state;
	try {
		return JSON.parse(trimmed);
	} catch {
		return state;
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}
