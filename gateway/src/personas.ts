import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { splitFrontmatter } from "./frontmatter.ts";
import { defaultInstructions } from "./prompt.ts";
import { CODEMODE, TOOL_NAMES } from "./tools.ts";

export const DEFAULT_PERSONA_NAME = "default";

export type Persona = {
	readonly name: string;
	readonly description: string;
	readonly model: string | null;
	readonly tools: readonly string[] | null;
	readonly instructions: string;
	readonly source: "builtin" | "file";
	readonly warnings: readonly string[];
};

const CLAUDE_MODEL_ALIASES = new Set(["sonnet", "opus", "haiku", "inherit"]);

const TOOL_ALIASES: Readonly<Record<string, string>> = {
	agent: "agent",
	judge: "judge",
	task: "agent",
	read: "read",
	write: "write",
	edit: "edit",
	bash: "bash",
	grep: "bash",
	glob: "bash",
	codemode: CODEMODE,
};

export function builtinPersona(): Persona {
	return {
		name: DEFAULT_PERSONA_NAME,
		description: "General coding assistant with every tool",
		model: null,
		tools: null,
		instructions: defaultInstructions(TOOL_NAMES),
		source: "builtin",
		warnings: [],
	};
}

export async function loadPersonas(directory: string): Promise<Persona[]> {
	const fromFiles = await readPersonaFiles(directory);
	const overridden = fromFiles.some((persona) => persona.name === DEFAULT_PERSONA_NAME);
	const rest = fromFiles.filter((persona) => persona.name !== DEFAULT_PERSONA_NAME);
	const base = fromFiles.filter((persona) => persona.name === DEFAULT_PERSONA_NAME);
	return [...(overridden ? base : [builtinPersona()]), ...rest.sort((a, b) => a.name.localeCompare(b.name))];
}

export async function findPersona(directory: string, name: string): Promise<Persona> {
	const personas = await loadPersonas(directory);
	const found = personas.find((persona) => persona.name === name);
	if (!found) throw new Error(`unknown persona ${name}`);
	return found;
}

export function parsePersona(fileName: string, text: string): Persona {
	const { fields, body } = splitFrontmatter(text);
	const warnings: string[] = [];
	const name = (fields.name ?? fileName.replace(/\.md$/i, "")).trim();
	const model = fields.model && !CLAUDE_MODEL_ALIASES.has(fields.model.trim().toLowerCase()) ? fields.model.trim() : null;
	return {
		name,
		description: fields.description?.trim() ?? "",
		model,
		tools: fields.tools === undefined ? null : mapTools(fields.tools, warnings),
		instructions: body.trim(),
		source: "file",
		warnings,
	};
}

async function readPersonaFiles(directory: string): Promise<Persona[]> {
	let entries: string[];
	try {
		entries = await readdir(directory);
	} catch {
		return [];
	}
	const files = entries.filter((entry) => entry.toLowerCase().endsWith(".md")).sort();
	const personas = await Promise.all(
		files.map(async (file) => {
			try {
				return parsePersona(file, await readFile(join(directory, file), "utf8"));
			} catch {
				return undefined;
			}
		}),
	);
	return personas.flatMap((persona) => (persona ? [persona] : []));
}

function mapTools(list: string, warnings: string[]): string[] {
	const names = new Set<string>([CODEMODE]);
	for (const entry of splitTopLevel(list)) {
		const base = entry.replace(/\(.*$/s, "").trim().toLowerCase();
		if (base === "") continue;
		const mapped = TOOL_ALIASES[base];
		if (mapped) names.add(mapped);
		else warnings.push(`unsupported tool ${entry.trim()}`);
	}
	return [...names];
}

function splitTopLevel(list: string): string[] {
	const parts: string[] = [];
	let depth = 0;
	let current = "";
	for (const char of list) {
		if (char === "(") depth += 1;
		if (char === ")") depth -= 1;
		if (char === "," && depth === 0) {
			parts.push(current);
			current = "";
		} else {
			current += char;
		}
	}
	parts.push(current);
	return parts;
}
