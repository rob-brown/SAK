import { homedir } from "node:os";
import { join } from "node:path";

export type Config = {
	readonly apiKey: string;
	readonly baseUrl: string;
	readonly cwd: string;
	readonly dbPath: string;
	readonly modelId: string;
	readonly personasDir: string;
};

export function loadConfig(env: NodeJS.ProcessEnv): Config {
	return {
		apiKey: env.SAK_API_KEY ?? "sak",
		baseUrl: env.SAK_BASE_URL ?? "http://localhost:1234/v1",
		cwd: env.SAK_CWD ?? process.cwd(),
		dbPath: env.SAK_DB ?? "./sak.sqlite",
		modelId: env.SAK_MODEL ?? "ornith-1.5-35b-a3b",
		personasDir: join(env.SAK_CONFIG_DIR ?? join(env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "sak"), "personas"),
	};
}
