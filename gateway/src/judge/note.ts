import { defineEntry, type ToolExecutionApi } from "@earendil-works/pi-durable";

export const JUDGE_KIND = "sak.judge";

export type JudgeNote = {
	acted: boolean;
	detail: string | null;
	model: string;
	ms: number;
	outcome: string;
	probability: number | null;
	purpose: "permission" | "persona pick" | "skill suggestion";
};

export const JudgeNoteEntry = defineEntry<JudgeNote>(JUDGE_KIND);

type Context = Parameters<ToolExecutionApi["agent"]>[0];

export async function recordFromTool(api: ToolExecutionApi, context: Context, note: JudgeNote): Promise<void> {
	try {
		await api.commit((tx) => tx.appendEntry(JudgeNoteEntry, api.conversationId, { data: note }), context);
	} catch (error) {
		if (context.abortSignal?.aborted) throw error;
	}
}

export function noteFor(
	purpose: JudgeNote["purpose"],
	model: string,
	started: number,
	result: Pick<JudgeNote, "acted" | "outcome"> & Partial<Pick<JudgeNote, "detail" | "probability">>,
): JudgeNote {
	return {
		purpose,
		model,
		ms: Date.now() - started,
		acted: result.acted,
		outcome: result.outcome,
		detail: result.detail ?? null,
		probability: result.probability ?? null,
	};
}
