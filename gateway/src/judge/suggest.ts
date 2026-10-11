import { discoverSkills } from "../skills.ts";
import { type InternalJudge, pickMany } from "./internal.ts";

export const SUGGESTION_TIMEOUT_MS = 3000;
export const MIN_MESSAGE_CHARS = 12;
export const SUGGESTION_TAG = "skill-suggestion";

const NONE = "none";

export type SuggestionDeps = InternalJudge & { readonly configDir: string };

export async function suggestSkill(
	deps: SuggestionDeps,
	text: string,
	cwd: string,
	signal?: AbortSignal,
): Promise<string | undefined> {
	if (text.trim().length < MIN_MESSAGE_CHARS || text.startsWith(`<${SUGGESTION_TAG}`)) return undefined;
	const { skills } = await discoverSkills(cwd, deps.configDir);
	if (skills.length === 0) return undefined;
	const options = { [NONE]: "No skill is needed, or none of them fits", ...describe(skills) };
	const timeout = AbortSignal.timeout(SUGGESTION_TIMEOUT_MS);
	try {
		const answers = await pickMany(
			deps.client,
			text,
			{ skill: { instructions: "Which skill, if any, would help with this request?", options } },
			signal ? AbortSignal.any([signal, timeout]) : timeout,
		);
		const pick = answers.skill;
		if (pick === undefined || pick.choice === NONE || pick.probability < deps.minConfidence) return undefined;
		return withSuggestion(pick.choice, pick.probability, text);
	} catch {
		return undefined;
	}
}

export function withSuggestion(name: string, confidence: number, text: string): string {
	const note = `A decision model judged that the "${name}" skill fits this request. If you agree, read its SKILL.md before starting.`;
	return `<${SUGGESTION_TAG} name="${name}" confidence="${confidence.toFixed(2)}">${note}</${SUGGESTION_TAG}>\n\n${text}`;
}

function describe(skills: readonly { name: string; description: string }[]): Record<string, string> {
	return Object.fromEntries(skills.map((skill) => [skill.name, skill.description]));
}
