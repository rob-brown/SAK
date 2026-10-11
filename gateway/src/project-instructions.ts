import { readFile, stat } from "node:fs/promises";
import { dirname, join } from "node:path";

export const MAX_FILE_CHARS = 20_000;
export const FILE_NAMES = ["AGENTS.md", "CLAUDE.md"] as const;

export type InstructionFile = {
	readonly path: string;
	readonly text: string;
};

export async function discoverInstructions(cwd: string, configDir: string): Promise<InstructionFile[]> {
	const directories = [configDir, ...(await directoriesFromRoot(cwd))];
	const found = await Promise.all(directories.map(readInstructionFile));
	return found.flatMap((file) => (file ? [file] : []));
}

export function renderInstructions(files: readonly InstructionFile[]): string | undefined {
	if (files.length === 0) return undefined;
	const blocks = files.map((file) => `<instructions path="${file.path}">\n${file.text}\n</instructions>`);
	const preface = "Instruction files follow; when they conflict, later files take precedence over earlier ones.";
	return `<project_instructions>\n${[preface, ...blocks].join("\n\n")}\n</project_instructions>`;
}

export async function directoriesFromRoot(cwd: string): Promise<string[]> {
	const chain: string[] = [];
	let current = cwd;
	for (;;) {
		chain.push(current);
		if (await exists(join(current, ".git"))) return chain.reverse();
		const parent = dirname(current);
		if (parent === current) return [cwd];
		current = parent;
	}
}

async function readInstructionFile(directory: string): Promise<InstructionFile | undefined> {
	for (const name of FILE_NAMES) {
		const path = join(directory, name);
		const text = await readText(path);
		if (text !== undefined) return { path, text: clip(text.trim()) };
	}
	return undefined;
}

async function readText(path: string): Promise<string | undefined> {
	try {
		const text = await readFile(path, "utf8");
		return text.trim() === "" ? undefined : text;
	} catch {
		return undefined;
	}
}

async function exists(path: string): Promise<boolean> {
	try {
		await stat(path);
		return true;
	} catch {
		return false;
	}
}

function clip(text: string): string {
	if (text.length <= MAX_FILE_CHARS) return text;
	return `${text.slice(0, MAX_FILE_CHARS)}\n… truncated (${text.length - MAX_FILE_CHARS} more characters)`;
}
