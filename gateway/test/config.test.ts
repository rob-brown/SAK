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
	const typed = loadConfig({ SAK_CONFIG_DIR: wrongType });
	const broken = loadConfig({ SAK_CONFIG_DIR: malformed });

	// Assert
	await assert.rejects(typed, /config\.toml: instructions\.max_file_chars must be a positive integer/);
	await assert.rejects(broken, /config\.toml/);
});
