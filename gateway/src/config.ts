import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { parse } from "smol-toml";
import { MAX_FILE_CHARS } from "./project-instructions.ts";

export const CONFIG_FILE = "config.toml";

export type Config = {
	readonly apiKey: string;
	readonly baseUrl: string;
	readonly configDir: string;
	readonly cwd: string;
	readonly dbPath: string;
	readonly instructionMaxChars: number;
	readonly modelId: string;
	readonly personasDir: string;
	readonly warnings: readonly string[];
};

type Kind = "count" | "text";
type Values = ReadonlyMap<string, number | string>;

const SCHEMA: Readonly<Record<string, Readonly<Record<string, Kind>>>> = {
	endpoint: { base_url: "text", model: "text" },
	instructions: { max_file_chars: "count" },
	storage: { db: "text" },
};

export async function loadConfig(env: NodeJS.ProcessEnv): Promise<Config> {
	const configDir = env.SAK_CONFIG_DIR ?? join(env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "sak");
	const { values, warnings } = await readSettings(join(configDir, CONFIG_FILE));
	return {
		apiKey: env.SAK_API_KEY ?? "sak",
		baseUrl: env.SAK_BASE_URL ?? text(values, "endpoint.base_url") ?? "http://localhost:1234/v1",
		configDir,
		cwd: env.SAK_CWD ?? process.cwd(),
		dbPath: env.SAK_DB ?? text(values, "storage.db") ?? "./sak.sqlite",
		instructionMaxChars: count(values, "instructions.max_file_chars") ?? MAX_FILE_CHARS,
		modelId: env.SAK_MODEL ?? text(values, "endpoint.model") ?? "ornith-1.5-35b-a3b",
		personasDir: join(configDir, "personas"),
		warnings,
	};
}

export function validateSettings(path: string, parsed: Record<string, unknown>) {
	const values = new Map<string, number | string>();
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
			values.set(`${section}.${key}`, value as number | string);
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
	if (kind === "text") return typeof value === "string" && value.trim() !== "";
	return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function describeKind(kind: Kind): string {
	return kind === "text" ? "a non-empty string" : "a positive integer";
}

function text(values: Values, key: string): string | undefined {
	const value = values.get(key);
	return typeof value === "string" ? value : undefined;
}

function count(values: Values, key: string): number | undefined {
	const value = values.get(key);
	return typeof value === "number" ? value : undefined;
}
