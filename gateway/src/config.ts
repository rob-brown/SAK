import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { parse } from "smol-toml";
import type { JudgeSettings } from "./judge/client.ts";
import { type Mode, MODES, parseRule, type Policy } from "./permissions/rules.ts";
import { MAX_FILE_CHARS } from "./project-instructions.ts";

export const CONFIG_FILE = "config.toml";

export type Config = {
	readonly apiKey: string;
	readonly baseUrl: string;
	readonly configDir: string;
	readonly cwd: string;
	readonly dbPath: string;
	readonly instructionMaxChars: number;
	readonly judge: JudgeSettings & {
		readonly enabled: boolean;
		readonly minConfidence: number;
		readonly pickPersonas: boolean;
		readonly suggestSkills: boolean;
	};
	readonly modelId: string;
	readonly permissions: Policy;
	readonly personasDir: string;
	readonly subagentLimit: number;
	readonly warnings: readonly string[];
};

type Kind = "count" | "flag" | "list" | "mode" | "ratio" | "text";
type Value = boolean | number | string | string[];
type Values = ReadonlyMap<string, Value>;

const SCHEMA: Readonly<Record<string, Readonly<Record<string, Kind>>>> = {
	endpoint: { base_url: "text", model: "text" },
	instructions: { max_file_chars: "count" },
	judge: {
		base_url: "text",
		enabled: "flag",
		min_confidence: "ratio",
		model: "text",
		pick_personas: "flag",
		suggest_skills: "flag",
		timeout_ms: "count",
	},
	permissions: { allow: "list", ask: "list", deny: "list", mode: "mode" },
	storage: { db: "text" },
	subagents: { max_concurrent: "count" },
};

export const DEFAULT_SUBAGENT_LIMIT = 6;
export const DEFAULT_JUDGE_URL = "http://localhost:11435";
export const DEFAULT_JUDGE_MODEL = "winnow:e4b";
export const DEFAULT_JUDGE_TIMEOUT_MS = 30_000;
export const DEFAULT_JUDGE_CONFIDENCE = 0.7;

export async function loadConfig(env: NodeJS.ProcessEnv): Promise<Config> {
	const configDir = env.SAK_CONFIG_DIR ?? join(env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "sak");
	const path = join(configDir, CONFIG_FILE);
	const { values, warnings } = await readSettings(path);
	return {
		apiKey: env.SAK_API_KEY ?? "sak",
		baseUrl: env.SAK_BASE_URL ?? text(values, "endpoint.base_url") ?? "http://localhost:1234/v1",
		configDir,
		cwd: env.SAK_CWD ?? process.cwd(),
		dbPath: env.SAK_DB ?? text(values, "storage.db") ?? "./sak.sqlite",
		instructionMaxChars: count(values, "instructions.max_file_chars") ?? MAX_FILE_CHARS,
		judge: {
			enabled: flag(values, "judge.enabled") ?? false,
			minConfidence: ratio(values, "judge.min_confidence") ?? DEFAULT_JUDGE_CONFIDENCE,
			pickPersonas: flag(values, "judge.pick_personas") ?? true,
			suggestSkills: flag(values, "judge.suggest_skills") ?? true,
			baseUrl: env.SAK_JUDGE_URL ?? text(values, "judge.base_url") ?? DEFAULT_JUDGE_URL,
			model: env.SAK_JUDGE_MODEL ?? text(values, "judge.model") ?? DEFAULT_JUDGE_MODEL,
			timeoutMs: count(values, "judge.timeout_ms") ?? DEFAULT_JUDGE_TIMEOUT_MS,
			...(env.SAK_JUDGE_API_KEY ? { apiKey: env.SAK_JUDGE_API_KEY } : {}),
		},
		modelId: env.SAK_MODEL ?? text(values, "endpoint.model") ?? "ornith-1.5-35b-a3b",
		permissions: policyFrom(path, values),
		personasDir: join(configDir, "personas"),
		subagentLimit: count(values, "subagents.max_concurrent") ?? DEFAULT_SUBAGENT_LIMIT,
		warnings,
	};
}

function policyFrom(path: string, values: Values): Policy {
	try {
		return {
			mode: (text(values, "permissions.mode") as Mode | undefined) ?? "ask",
			allow: (list(values, "permissions.allow") ?? []).map(parseRule),
			ask: (list(values, "permissions.ask") ?? []).map(parseRule),
			deny: (list(values, "permissions.deny") ?? []).map(parseRule),
		};
	} catch (error) {
		throw new Error(`${path}: ${error instanceof Error ? error.message : String(error)}`);
	}
}

export function validateSettings(path: string, parsed: Record<string, unknown>) {
	const values = new Map<string, Value>();
	const warnings: string[] = [];
	for (const [section, table] of Object.entries(parsed)) {
		const keys = SCHEMA[section];
		if (keys === undefined) {
			warnings.push(`${path}: unknown section [${section}]`);
			continue;
		}
		if (typeof table !== "object" || table === null || Array.isArray(table)) {
			throw new Error(`${path}: [${section}] must be a table`);
		}
		for (const [key, value] of Object.entries(table)) {
			const kind = keys[key];
			if (kind === undefined) {
				warnings.push(`${path}: unknown key ${section}.${key}`);
				continue;
			}
			if (!matches(kind, value)) throw new Error(`${path}: ${section}.${key} must be ${describeKind(kind)}`);
			values.set(`${section}.${key}`, value as Value);
		}
	}
	return { values: values as Values, warnings };
}

async function readSettings(path: string) {
	let source: string;
	try {
		source = await readFile(path, "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return { values: new Map() as Values, warnings: [] };
		throw error;
	}
	let parsed: Record<string, unknown>;
	try {
		parsed = parse(source);
	} catch (error) {
		throw new Error(`${path}: ${error instanceof Error ? error.message : String(error)}`);
	}
	return validateSettings(path, parsed);
}

function matches(kind: Kind, value: unknown): boolean {
	if (kind === "flag") return typeof value === "boolean";
	if (kind === "ratio") return typeof value === "number" && value > 0 && value <= 1;
	if (kind === "text") return typeof value === "string" && value.trim() !== "";
	if (kind === "mode") return (MODES as readonly unknown[]).includes(value);
	if (kind === "list") return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim() !== "");
	return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function describeKind(kind: Kind): string {
	if (kind === "flag") return "true or false";
	if (kind === "ratio") return "a number above 0 and at most 1";
	if (kind === "text") return "a non-empty string";
	if (kind === "mode") return `one of ${MODES.join(", ")}`;
	if (kind === "list") return "a list of non-empty strings";
	return "a positive integer";
}

function ratio(values: Values, key: string): number | undefined {
	const value = values.get(key);
	return typeof value === "number" ? value : undefined;
}

function flag(values: Values, key: string): boolean | undefined {
	const value = values.get(key);
	return typeof value === "boolean" ? value : undefined;
}

function list(values: Values, key: string): string[] | undefined {
	const value = values.get(key);
	return Array.isArray(value) ? value : undefined;
}

function text(values: Values, key: string): string | undefined {
	const value = values.get(key);
	return typeof value === "string" ? value : undefined;
}

function count(values: Values, key: string): number | undefined {
	const value = values.get(key);
	return typeof value === "number" ? value : undefined;
}
