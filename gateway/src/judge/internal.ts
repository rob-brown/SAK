import type { JudgeClient } from "./client.ts";

export type InternalJudge = {
	readonly client: JudgeClient;
	readonly minConfidence: number;
};

export type Pick = {
	readonly choice: string;
	readonly probability: number;
};

export type Choice = {
	readonly instructions: string;
	readonly options: Readonly<Record<string, string>>;
};

export async function pickMany(
	client: JudgeClient,
	state: unknown,
	choices: Readonly<Record<string, Choice>>,
	signal?: AbortSignal,
): Promise<Record<string, Pick | undefined>> {
	const questions = Object.fromEntries(
		Object.entries(choices).map(([id, choice]) => [
			id,
			{ type: "choice" as const, instructions: choice.instructions, criteria: choice.options },
		]),
	);
	const { answers } = await client.evaluate(state, questions, signal);
	return Object.fromEntries(
		Object.entries(choices).map(([id, choice]) => [id, toPick(answers[id], Object.keys(choice.options))]),
	);
}

function toPick(answer: unknown, allowed: readonly string[]): Pick | undefined {
	if (typeof answer !== "object" || answer === null) return undefined;
	const { choice, probabilities } = answer as { choice?: unknown; probabilities?: Record<string, unknown> };
	if (typeof choice !== "string" || !allowed.includes(choice)) return undefined;
	const probability = probabilities?.[choice];
	return typeof probability === "number" ? { choice, probability } : undefined;
}
