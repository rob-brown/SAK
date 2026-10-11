import { createHash } from "node:crypto";
import type { ToolExecutionApi } from "@earendil-works/pi-durable";
import { type Choice, type InternalJudge, pickMany } from "../judge/internal.ts";
import { noteFor, recordFromTool } from "../judge/note.ts";
import { DEFAULT_PERSONA_NAME, loadPersonas, type Persona } from "../personas.ts";

type Context = Parameters<ToolExecutionApi["agent"]>[0];

const BATCH = 20;

export type Selection = {
	readonly api: ToolExecutionApi;
	readonly context: Context;
	readonly explicit: Persona | undefined;
	readonly judge: InternalJudge | undefined;
	readonly keys: readonly string[];
	readonly personasDir: string;
	readonly prompts: readonly string[];
};

export async function personasFor(selection: Selection): Promise<Persona[]> {
	const { explicit, judge, personasDir, prompts } = selection;
	if (explicit !== undefined) return prompts.map(() => explicit);
	const available = await loadPersonas(personasDir);
	const fallback = available.find((persona) => persona.name === DEFAULT_PERSONA_NAME) as Persona;
	if (judge === undefined || available.length < 2) return prompts.map(() => fallback);
	const names = await chosenNames(selection, judge, available, fallback);
	return names.map((name) => available.find((persona) => persona.name === name) ?? fallback);
}

export async function closestPersona(
	{ api, context, judge, personasDir }: Pick<Selection, "api" | "context" | "judge" | "personasDir">,
	wanted: string,
): Promise<Persona | undefined> {
	const available = await loadPersonas(personasDir);
	const exact = available.find((persona) => persona.name === wanted);
	if (exact !== undefined || judge === undefined) return exact;
	const fallback = available.find((persona) => persona.name === DEFAULT_PERSONA_NAME) as Persona;
	const key = `persona-hint:${createHash("sha256").update(wanted).digest("hex").slice(0, 16)}`;
	const known = await api.memo<string>(key, context);
	const name = known ?? (await api.memo<string>(key, await pickClosest(judge, available, fallback, wanted), context));
	return available.find((persona) => persona.name === name) ?? fallback;
}

async function pickClosest(
	judge: InternalJudge,
	available: readonly Persona[],
	fallback: Persona,
	wanted: string,
): Promise<string> {
	const options: Record<string, string> = Object.fromEntries(
		available.map((persona) => [persona.name, persona.description || persona.name]),
	);
	const choices: Record<string, Choice> = {
		closest: {
			instructions: `Which persona best matches the role described in \`wanted\`? Choose "${fallback.name}" unless a specialised persona clearly fits.`,
			options,
		},
	};
	const { answers } = await askJudge(judge, { wanted }, choices);
	const answer = answers.closest;
	return answer !== undefined && answer.probability >= judge.minConfidence ? answer.choice : fallback.name;
}

async function chosenNames(
	{ api, context, keys, prompts }: Selection,
	judge: InternalJudge,
	available: readonly Persona[],
	fallback: Persona,
): Promise<string[]> {
	const names = await Promise.all(keys.map((key) => api.memo<string>(`persona:${key}`, context)));
	const open = names.flatMap((name, index) => (name === undefined ? [index] : []));
	const started = Date.now();
	const { picked, failed } = await judgeBatches(open, prompts, judge, available, fallback.name);
	if (open.length > 0) {
		const chosen = [...picked].filter(([, choice]) => choice.name !== fallback.name);
		const summary = [...picked]
			.map(([index, choice]) => `${index + 1}: ${choice.name} (${Math.round(choice.confidence * 100)}%)`)
			.join(", ");
		const outcome = failed
			? "judge unavailable, kept the default persona"
			: chosen.length > 0
				? `chose a persona for ${chosen.length} of ${open.length} prompts`
				: "kept the default persona";
		const note = noteFor("persona pick", judge.client.model, started, {
			acted: chosen.length > 0,
			outcome,
			detail: summary,
		});
		await recordFromTool(api, context, note);
	}
	for (const [index, choice] of picked) {
		const stored = await api.memo<string>(`persona:${keys[index]}`, choice.name, context);
		names[index] = stored;
		if (stored !== fallback.name) {
			api.diagnostic({
				severity: "info",
				message: `persona ${stored} chosen for prompt ${index + 1} (${Math.round(choice.confidence * 100)}% sure)`,
			});
		}
	}
	return names.map((name) => name ?? fallback.name);
}

async function judgeBatches(
	open: readonly number[],
	prompts: readonly string[],
	judge: InternalJudge,
	available: readonly Persona[],
	fallback: string,
): Promise<{ picked: Map<number, { name: string; confidence: number }>; failed: boolean }> {
	const picked = new Map<number, { name: string; confidence: number }>();
	let failed = false;
	const options: Record<string, string> = Object.fromEntries(
		available.map((persona) => [persona.name, persona.description || persona.name]),
	);
	for (let start = 0; start < open.length; start += BATCH) {
		const slice = open.slice(start, start + BATCH);
		const choices: Record<string, Choice> = Object.fromEntries(
			slice.map((_, position) => [
				`t${position}`,
				{
					instructions: `Which persona is best suited to do the task in \`tasks[${position}]\`? Choose "${fallback}" unless a specialised persona clearly fits.`,
					options,
				},
			]),
		);
		const { answers, unavailable } = await askJudge(judge, { tasks: slice.map((index) => prompts[index]) }, choices);
		failed ||= unavailable;
		slice.forEach((index, position) => {
			const answer = answers[`t${position}`];
			const confident = answer !== undefined && answer.probability >= judge.minConfidence;
			picked.set(index, { name: confident ? answer.choice : fallback, confidence: answer?.probability ?? 0 });
		});
	}
	return { picked, failed };
}

async function askJudge(judge: InternalJudge, state: unknown, choices: Record<string, Choice>) {
	try {
		return { answers: await pickMany(judge.client, state, choices), unavailable: false };
	} catch {
		return { answers: {} as Record<string, undefined>, unavailable: true };
	}
}
