import { createHash } from "node:crypto";
import {
	type Agent,
	type AgentChange,
	configure,
	defineExtension,
	defineTool,
	type Extension,
	type ToolExecutionApi,
	type Tx,
} from "@earendil-works/pi-durable";
import { DEFAULT_PERSONA_NAME, findPersona, type Persona } from "../personas.ts";
import { toolsNamed } from "../tools.ts";
import { AGENT, DESCRIPTION, PARAMETERS } from "./catalog.ts";
import type { Semaphore } from "./semaphore.ts";

type Context = Parameters<ToolExecutionApi["agent"]>[0];
type Block = { readonly type: string; readonly text?: string };

export type SubagentDeps = {
	readonly personasDir: string;
	readonly semaphore: Semaphore;
};

export function subagentExtension({ personasDir, semaphore }: SubagentDeps) {
	const occurrences = new Map<string, number>();

	const tool = defineTool({
		name: AGENT,
		description: DESCRIPTION,
		parameters: PARAMETERS,
		replay: "safe",
		executionMode: "sequential",
		execute: async (args, api, context) => {
			const persona = await findPersona(personasDir, args.persona ?? DEFAULT_PERSONA_NAME).catch(
				(error: unknown) => error as Error,
			);
			if (persona instanceof Error) return failure(persona.message);
			const parent = await api.agent(context);
			const keys = args.prompts.map((prompt) => nextKey(occurrences, api.taskId, prompt, persona.name));
			const answers = await Promise.all(
				args.prompts.map((prompt, index) =>
					semaphore.run(() => runChild(api, context, { prompt, key: keys[index] as string, persona, parent, extension })),
				),
			);
			return { content: [{ type: "text", text: JSON.stringify(answers) }] };
		},
	});

	const extension: Extension = defineExtension({ name: "subagents", tools: [tool] });
	return extension;
}

type Run = {
	readonly prompt: string;
	readonly key: string;
	readonly persona: Persona;
	readonly parent: Agent;
	readonly extension: Extension;
};

async function runChild(api: ToolExecutionApi, context: Context, run: Run): Promise<string> {
	if (context.abortSignal?.aborted) throw new Error("aborted");
	try {
		const childId = await childFor(api, context, run);
		const conversation = await api.conversation(childId as never, context);
		if (conversation === undefined) return "Error: subagent conversation is missing";
		const request = { type: "input", content: run.prompt, requestId: `subagent:${api.taskId}:${run.key}` } as const;
		const settled = await (await conversation.submit(request, context)).wait(context);
		if (settled.status !== "done") return `Error: ${settled.reason ?? "no answer"}`;
		return await api.commit((tx) => answerText(tx, settled.answer), context);
	} catch (error) {
		if (context.abortSignal?.aborted) throw error;
		return `Error: ${error instanceof Error ? error.message : String(error)}`;
	}
}

async function childFor(api: ToolExecutionApi, context: Context, run: Run): Promise<number> {
	const known = await api.memo<number>(run.key, context);
	if (known !== undefined) return known;
	const created = await api.commit(async (tx) => {
		const child = await tx.createConversation({ ownership: { kind: "task", taskId: api.taskId } });
		await configure(tx, child.id, changeFor(run));
		return Number(child.id);
	}, context);
	return await api.memo<number>(run.key, created, context);
}

function changeFor({ persona, parent, extension }: Run): AgentChange {
	const offered = parent.tools.map((tool) => tool.name).filter((name) => name !== AGENT);
	const wanted = persona.tools ? offered.filter((name) => persona.tools?.includes(name)) : offered;
	return {
		extensions: { remove: [extension] },
		instructions: persona.instructions,
		tools: toolsNamed(wanted),
		...(persona.model && parent.model ? { model: { provider: parent.model.provider, modelId: persona.model } } : {}),
	};
}

async function answerText(tx: Tx, answer: unknown): Promise<string> {
	const entry = await tx.entry(answer as never);
	const messages = (entry as { model?: { role: string; content: unknown }[] } | undefined)?.model ?? [];
	const message = [...messages].reverse().find((candidate) => candidate.role === "assistant");
	const blocks = Array.isArray(message?.content) ? (message.content as Block[]) : [];
	return blocks
		.filter((block) => block.type === "text")
		.map((block) => block.text ?? "")
		.join("\n")
		.trim();
}

function nextKey(occurrences: Map<string, number>, taskId: unknown, prompt: string, persona: string): string {
	const digest = createHash("sha256").update(`${persona}\n${prompt}`).digest("hex").slice(0, 16);
	const slot = `${String(taskId)}:${digest}`;
	const count = occurrences.get(slot) ?? 0;
	occurrences.set(slot, count + 1);
	return `child:${digest}:${count}`;
}

function failure(message: string) {
	return { content: [{ type: "text" as const, text: message }], isError: true };
}
