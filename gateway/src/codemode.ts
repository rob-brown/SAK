import { Type } from "@earendil-works/pi-ai";
import { type CodemodeJsonSchema, CodemodeSandbox, type CodemodeTool } from "@earendil-works/pi-codemode";
import { defineExtension, defineTool, type ToolExecutionApi, type ToolRegistration } from "@earendil-works/pi-durable";

const TOOL_NAME = "codemode";
const TIMEOUT_MS = 60_000;
const MAX_OUTPUT_CHARS = 40_000;

type Context = Parameters<ToolRegistration["execute"]>[2];

const DESCRIPTION = [
	"Run a JavaScript script that calls the other tools. Only the script's output and return value reach you, so use it to batch many calls or to filter large results.",
	"The script is the body of an async function: top-level await and return work. Call tools as `tools.<name>(args)`, add output with `text(value)` or `console.log`.",
	"The sandbox has no file system, network or timers; the tools are its only capability.",
].join("\n");

export const Codemode = defineTool({
	name: TOOL_NAME,
	description: DESCRIPTION,
	parameters: Type.Object({
		code: Type.String({ description: "JavaScript source: the body of an async function" }),
	}),
	executionMode: "sequential",
	execute: async (args, api, context) => {
		const agent = await api.agent(context);
		const nested = agent.tools.filter((tool) => tool.name !== TOOL_NAME);
		const sandbox = new CodemodeSandbox({ timeoutMs: TIMEOUT_MS, tools: nested.map((tool) => bridge(tool, api, context)) });
		try {
			const result = await sandbox.execute(args.code);
			const text = format(result);
			return { content: [{ type: "text", text }], isError: !result.ok };
		} finally {
			await sandbox.close();
		}
	},
});

export const CodemodeExtension = defineExtension({ name: "codemode", tools: [Codemode] });

function describe(tool: ToolRegistration): CodemodeTool {
	return {
		name: tool.name,
		description: tool.description,
		inputSchema: tool.parameters as unknown as CodemodeJsonSchema,
		execute: async () => "",
	};
}

function bridge(tool: ToolRegistration, api: ToolExecutionApi, context: Context): CodemodeTool {
	return {
		...describe(tool),
		execute: async (callArgs) => {
			const chunks: string[] = [];
			const decoder = new TextDecoder();
			const nestedApi: ToolExecutionApi = {
				...api,
				output: (chunk) => {
					chunks.push(typeof chunk === "string" ? chunk : decoder.decode(chunk));
				},
				outputWindow: undefined,
				details: async () => {},
				diagnostic: () => {},
			};
			const result = await tool.execute(callArgs as never, nestedApi, context);
			const text = result.content
				? result.content.map((block) => (block.type === "text" ? block.text : "")).join("\n")
				: chunks.join("");
			if (result.isError) throw new Error(text || `${tool.name} failed`);
			return text;
		},
	};
}

type Outcome = Awaited<ReturnType<CodemodeSandbox["execute"]>>;

function format(result: Outcome): string {
	const lines = [result.ok ? "Script completed" : "Script failed"];
	for (const item of result.output) {
		if (item.type === "text") lines.push(item.text);
	}
	if (result.ok && result.value !== undefined) {
		lines.push(typeof result.value === "string" ? result.value : JSON.stringify(result.value));
	}
	if (!result.ok) lines.push(`Script error: ${result.error.kind}: ${result.error.message}`);
	const text = lines.join("\n");
	return text.length > MAX_OUTPUT_CHARS ? `${text.slice(0, MAX_OUTPUT_CHARS)}\n… output truncated` : text;
}
