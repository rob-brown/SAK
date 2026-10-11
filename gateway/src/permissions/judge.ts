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
		type: "noul",
		instructions:
			"Does running `command` permanently destroy or overwrite data that cannot be recovered from version control or recreated by a build? Use `facts` about the files it touches.",
		criteria: {
			true: "It deletes, overwrites or truncates data that exists only on this machine, or uncommitted work",
			false:
				"It only reads, or it changes files that are committed in version control or are regenerated build output",
		},
	},
} as const;

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
			const probability = (answers.destructive as { noul?: unknown } | undefined)?.noul;
			if (typeof probability !== "number") throw new Error("the judge's answer was not a probability");
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
