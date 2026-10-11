import type { JudgeClient } from "../judge/client.ts";
import { type JudgeNote, noteFor } from "../judge/note.ts";
import { gatherFacts } from "./facts.ts";
import type { Call } from "./rules.ts";

export const DEFAULT_THRESHOLD = 0.7;

export type Assessment = {
	readonly flagged: boolean;
	readonly message: string | undefined;
	readonly note: JudgeNote | undefined;
};

const NOT_FLAGGED: Assessment = { flagged: false, message: undefined, note: undefined };

const QUESTION = {
	destructive: {
		type: "score",
		instructions:
			"How much permanent data loss could running `command` cause? Data counts as lost only if it cannot be recovered from version control or recreated by a build. Use `facts` about the files it touches.",
		criteria: [
			"Harmless: it only reads, or changes nothing that matters",
			"Low risk: it changes files that are committed in version control or are regenerated build output",
			"Risky: it overwrites or removes files that may exist only on this machine",
			"Destructive: it deletes, overwrites or truncates uncommitted work or data that exists only on this machine, or damages the system",
		],
	},
} as const;

const TOP_LEVEL = QUESTION.destructive.criteria.length - 1;

export class PermissionJudge {
	private readonly client: JudgeClient;
	private readonly threshold: number;

	constructor(client: JudgeClient, threshold: number = DEFAULT_THRESHOLD) {
		this.client = client;
		this.threshold = threshold;
	}

	async assess(call: Call, cwd: string, signal?: AbortSignal): Promise<Assessment> {
		const command = call.arguments.command;
		if (call.name !== "bash" || typeof command !== "string") return NOT_FLAGGED;
		const started = Date.now();
		const record = (result: Parameters<typeof noteFor>[3]) => noteFor("permission", this.client.model, started, result);
		const facts = await gatherFacts(command, cwd);
		if (facts.onlyIgnoredTargets) {
			const note = record({ acted: false, outcome: "only git-ignored files inside the project", detail: facts.lines.join("; ") });
			return { flagged: false, message: undefined, note };
		}
		try {
			const state = { command, working_directory: cwd, facts: facts.lines };
			const { answers } = await this.client.evaluate(state, QUESTION, signal);
			const score = (answers.destructive as { score?: unknown } | undefined)?.score;
			if (typeof score !== "number") throw new Error("the judge's answer was not a score");
			const probability = Math.round(Math.min(Math.max(score / TOP_LEVEL, 0), 1) * 10_000) / 10_000;
			const flagged = probability >= this.threshold;
			const percent = Math.round(probability * 100);
			const note = record({
				acted: flagged,
				outcome: flagged ? "flagged as likely destructive" : "looks safe to run",
				probability,
				detail: facts.lines.join("; "),
			});
			const message = flagged ? `Flagged by the judge as likely destructive (${percent}%).` : undefined;
			return { flagged, message, note };
		} catch (error) {
			if (signal?.aborted) throw error;
			const note = record({ acted: true, outcome: "judge unavailable, asked a person", detail: String(error) });
			return { flagged: true, message: "The judge could not be reached, so this needs your decision.", note };
		}
	}
}
