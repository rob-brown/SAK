import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { CONFIG_FILE, loadConfig } from "../src/config.ts";
import { MAX_FILE_CHARS } from "../src/project-instructions.ts";

async function configDirWith(toml?: string) {
	const directory = await mkdtemp(join(tmpdir(), "sak-config-file-"));
	if (toml !== undefined) await writeFile(join(directory, CONFIG_FILE), toml);
	return directory;
}

test("without a config file the defaults apply and nothing is warned about", async () => {
	// Arrange
	const SAK_CONFIG_DIR = await configDirWith();

	// Act
	const config = await loadConfig({ SAK_CONFIG_DIR });

	// Assert
	assert.equal(config.baseUrl, "http://localhost:1234/v1");
	assert.equal(config.dbPath, "./sak.sqlite");
	assert.equal(config.instructionMaxChars, MAX_FILE_CHARS);
	assert.deepEqual(config.warnings, []);
});

test("file values replace the defaults and environment variables replace file values", async () => {
	// Arrange
	const SAK_CONFIG_DIR = await configDirWith(
		'[endpoint]\nbase_url = "http://file:1/v1"\nmodel = "from-file"\n[storage]\ndb = "/data/file.sqlite"\n[instructions]\nmax_file_chars = 500\n',
	);

	// Act
	const config = await loadConfig({ SAK_CONFIG_DIR, SAK_MODEL: "from-env" });

	// Assert
	assert.equal(config.baseUrl, "http://file:1/v1");
	assert.equal(config.modelId, "from-env");
	assert.equal(config.dbPath, "/data/file.sqlite");
	assert.equal(config.instructionMaxChars, 500);
});

test("unknown sections and keys are warned about and the rest of the file still applies", async () => {
	// Arrange
	const SAK_CONFIG_DIR = await configDirWith('[endpoint]\nmodel = "m"\nmodle = "typo"\n[extras]\nx = 1\n');

	// Act
	const config = await loadConfig({ SAK_CONFIG_DIR });

	// Assert
	assert.equal(config.modelId, "m");
	assert.equal(config.warnings.length, 2);
	assert.match(config.warnings.join("\n"), /endpoint\.modle/);
	assert.match(config.warnings.join("\n"), /\[extras\]/);
});

test("a wrong type or malformed TOML fails loudly and names the file", async () => {
	// Arrange
	const wrongType = await configDirWith("[instructions]\nmax_file_chars = -3\n");
	const malformed = await configDirWith("[endpoint\n");

	// Act
	const [typed, broken] = await Promise.allSettled([
		loadConfig({ SAK_CONFIG_DIR: wrongType }),
		loadConfig({ SAK_CONFIG_DIR: malformed }),
	]);

	// Assert
	assert.equal(typed.status, "rejected");
	assert.equal(broken.status, "rejected");
	assert.match(String((typed as PromiseRejectedResult).reason), /config\.toml: instructions\.max_file_chars must be a positive integer/);
	assert.match(String((broken as PromiseRejectedResult).reason), /config\.toml/);
});

test("permissions come from the file, and a bad mode or rule stops the load", async () => {
	// Arrange
	const good = await configDirWith('[permissions]\nmode = "accept-edits"\nallow = ["Bash(ls *)"]\ndeny = ["Bash(rm *)"]\n');
	const badMode = await configDirWith('[permissions]\nmode = "yolo"\n');
	const badRule = await configDirWith('[permissions]\nallow = ["(nope)"]\n');

	// Act
	const config = await loadConfig({ SAK_CONFIG_DIR: good });
	const results = await Promise.allSettled([
		loadConfig({ SAK_CONFIG_DIR: badMode }),
		loadConfig({ SAK_CONFIG_DIR: badRule }),
	]);

	// Assert
	assert.equal(config.permissions.mode, "accept-edits");
	assert.deepEqual(config.permissions.allow, [{ tool: "bash", pattern: "ls *" }]);
	assert.deepEqual(config.permissions.deny, [{ tool: "bash", pattern: "rm *" }]);
	assert.deepEqual(
		results.map((result) => result.status),
		["rejected", "rejected"],
	);
});

test("the subagent limit defaults to six and can be set in the file", async () => {
	// Arrange
	const bare = await configDirWith();
	const tuned = await configDirWith("[subagents]\nmax_concurrent = 3\n");

	// Act
	const [defaults, custom] = await Promise.all([
		loadConfig({ SAK_CONFIG_DIR: bare }),
		loadConfig({ SAK_CONFIG_DIR: tuned }),
	]);

	// Assert
	assert.equal(defaults.subagentLimit, 6);
	assert.equal(custom.subagentLimit, 3);
});

test("the judge is off by default, targets a local ollaya server, and the key comes only from the environment", async () => {
	// Arrange
	const bare = await configDirWith();
	const filed = await configDirWith(
		'[judge]\nenabled = true\nbase_url = "https://api.typesafe.ai"\nmodel = "jev-latest"\ntimeout_ms = 5000\napi_key = "nope"\n',
	);

	// Act
	const defaults = await loadConfig({ SAK_CONFIG_DIR: bare });
	const fromFile = await loadConfig({ SAK_CONFIG_DIR: filed, SAK_JUDGE_API_KEY: "from-env" });
	const overridden = await loadConfig({ SAK_CONFIG_DIR: filed, SAK_JUDGE_URL: "http://other:1", SAK_JUDGE_MODEL: "m" });

	// Assert
	assert.deepEqual(defaults.judge, {
		enabled: false,
		baseUrl: "http://localhost:11435",
		model: "winnow:e4b",
		timeoutMs: 30_000,
	});
	assert.deepEqual(fromFile.judge, {
		enabled: true,
		baseUrl: "https://api.typesafe.ai",
		model: "jev-latest",
		timeoutMs: 5000,
		apiKey: "from-env",
	});
	assert.match(fromFile.warnings.join("\n"), /unknown key judge\.api_key/);
	assert.deepEqual([overridden.judge.baseUrl, overridden.judge.model, overridden.judge.apiKey], ["http://other:1", "m", undefined]);
});

test("a judge flag that is not true or false stops the load", async () => {
	// Arrange
	const SAK_CONFIG_DIR = await configDirWith('[judge]\nenabled = "yes"\n');

	// Act
	const result = await loadConfig({ SAK_CONFIG_DIR }).catch((error: Error) => error);

	// Assert
	assert.match(String(result), /judge\.enabled must be true or false/);
});

test("without permission settings every call that is not a plain read asks", async () => {
	// Arrange
	const SAK_CONFIG_DIR = await configDirWith();

	// Act
	const { permissions } = await loadConfig({ SAK_CONFIG_DIR });

	// Assert
	assert.deepEqual(permissions, { mode: "ask", allow: [], ask: [], deny: [] });
});
