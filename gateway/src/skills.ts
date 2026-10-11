import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { splitFrontmatter } from "./frontmatter.ts";
import { directoriesFromRoot } from "./project-instructions.ts";

export const SKILL_FILE = "SKILL.md";
export const MAX_NAME_CHARS = 64;
export const MAX_DESCRIPTION_CHARS = 1024;

const NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export type Skill = {
	readonly name: string;
	readonly description: string;
	readonly path: string;
};

export type SkillDiscovery = {
	readonly skills: readonly Skill[];
	readonly warnings: readonly string[];
};

type Parsed = { readonly skill: Skill } | { readonly warning: string };

export async function discoverSkills(cwd: string, configDir: string): Promise<SkillDiscovery> {
	const projectRoots = (await directoriesFromRoot(cwd)).map((directory) => join(directory, ".agents", "skills"));
	const byName = new Map<string, Skill>();
	const warnings: string[] = [];
	for (const root of [join(configDir, "skills"), ...projectRoots]) {
		const found = await readSkillRoot(root);
		warnings.push(...found.warnings);
		for (const skill of found.skills) byName.set(skill.name, skill);
	}
	const skills = [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
	return { skills, warnings };
}

export function parseSkill(path: string, text: string): Parsed {
	const { fields } = splitFrontmatter(text);
	const name = unquote(fields.name ?? "");
	const description = unquote(fields.description ?? "");
	if (name.length === 0 || name.length > MAX_NAME_CHARS || !NAME_PATTERN.test(name)) {
		return { warning: `${path}: invalid name "${name}"` };
	}
	if (description.length === 0 || description === ">" || description === "|") {
		return { warning: `${path}: missing single-line description` };
	}
	if (description.length > MAX_DESCRIPTION_CHARS) {
		return { warning: `${path}: description over ${MAX_DESCRIPTION_CHARS} characters` };
	}
	return { skill: { name, description, path } };
}

export function renderSkills(skills: readonly Skill[]): string | undefined {
	if (skills.length === 0) return undefined;
	const preface =
		"Skills hold specialised instructions. When a task matches a skill's description, read its file at the given location with the read tool before proceeding, and resolve relative paths in it against its directory.";
	const entries = skills.map(
		(skill) =>
			`<skill name="${skill.name}" location="${escape(skill.path)}">${escape(skill.description)}</skill>`,
	);
	return `<skills>\n${[preface, ...entries].join("\n")}\n</skills>`;
}

async function readSkillRoot(root: string): Promise<{ skills: Skill[]; warnings: string[] }> {
	const skills: Skill[] = [];
	const warnings: string[] = [];
	for (const directory of await listDirectories(root)) {
		const path = join(root, directory, SKILL_FILE);
		const text = await readText(path);
		if (text === undefined) continue;
		const parsed = parseSkill(path, text);
		if ("skill" in parsed) skills.push(parsed.skill);
		else warnings.push(parsed.warning);
	}
	return { skills, warnings };
}

async function listDirectories(root: string): Promise<string[]> {
	try {
		const entries = await readdir(root, { withFileTypes: true });
		return entries
			.filter((entry) => entry.isDirectory() || entry.isSymbolicLink())
			.map((entry) => entry.name)
			.sort();
	} catch {
		return [];
	}
}

async function readText(path: string): Promise<string | undefined> {
	try {
		return await readFile(path, "utf8");
	} catch {
		return undefined;
	}
}

function unquote(value: string): string {
	const trimmed = value.trim();
	const quoted = /^(["'])([\s\S]*)\1$/.exec(trimmed);
	return quoted?.[2] ?? trimmed;
}

function escape(text: string): string {
	return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}
