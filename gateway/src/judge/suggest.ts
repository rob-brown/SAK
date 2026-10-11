import { discoverSkills } from "../skills.ts";
import { type InternalJudge, pickMany } from "./internal.ts";
import { type JudgeNote, noteFor } from "./note.ts";

export const SUGGESTION_TIMEOUT_MS = 3000;
export const MIN_MESSAGE_CHARS = 12;
export const SUGGESTION_TAG = "skill-suggestion";

const NONE = "none";

export type SuggestionDeps = InternalJudge & { readonly configDir: string };

export type Suggestion = {
	readonly content: string;
	readonly note: JudgeNote | undefined;
};

export async function suggestSkill(
	deps: SuggestionDeps,
	text: string,
	cwd: string,
	signal?: AbortSignal,
): Promise<Suggestion> {
	const unchanged: Suggestion = { content: text, note: undefined };
	if (text.trim().length < MIN_MESSAGE_CHARS || text.startsWith(`<${SUGGESTION_TAG}`)) return unchanged;
	const { skills } = await discoverSkills(cwd, deps.configDir);
	if (skills.length === 0) return unchanged;
	const options = { [NONE]: "No skill is needed, or none of them fits", ...describe(skills) };
	const timeout = AbortSignal.timeout(SUGGESTION_TIMEOUT_MS);
	const started = Date.now();
	const record = (result: Parameters<typeof noteFor>[3]) => noteFor("skill suggestion", deps.client.model, started, result);
	try {
		const answers = await pickMany(
			deps.client,
			text,
			{ skill: { instructions: "Which skill, if any, would help with this request?", options } },
			signal ? AbortSignal.any([signal, timeout]) : timeout,
		);
		const pick = answers.skill;
		if (pick === undefined) return { content: text, note: record({ acted: false, outcome: "unreadable answer" }) };
		const probability = pick.probability;
		if (pick.choice === NONE) return { content: text, note: record({ acted: false, outcome: "no skill fits", probability }) };
		if (probability < deps.minConfidence) {
			return { content: text, note: record({ acted: false, outcome: `not sure enough about ${pick.choice}`, probability }) };
		}
		return {
			content: withSuggestion(pick.choice, probability, text),
			note: record({ acted: true, outcome: `suggested ${pick.choice}`, probability }),
		};
	} catch (error) {
		return { content: text, note: record({ acted: false, outcome: "judge unavailable", detail: String(error) }) };
	}
}

export function withSuggestion(name: string, confidence: number, text: string): string {
	const note = `A decision model judged that the "${name}" skill fits this request. If you agree, read its SKILL.md before starting.`;
	return `<${SUGGESTION_TAG} name="${name}" confidence="${confidence.toFixed(2)}">${note}</${SUGGESTION_TAG}>\n\n${text}`;
}

function describe(skills: readonly { name: string; description: string }[]): Record<string, string> {
	return Object.fromEntries(skills.map((skill) => [skill.name, skill.description]));
}
