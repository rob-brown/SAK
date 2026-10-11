import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { discoverInstructions, MAX_FILE_CHARS, renderInstructions } from "../src/project-instructions.ts";

async function repo() {
	const root = await mkdtemp(join(tmpdir(), "sak-repo-"));
	await mkdir(join(root, ".git"));
	const nested = join(root, "packages", "app");
	await mkdir(nested, { recursive: true });
	const configDir = await mkdtemp(join(tmpdir(), "sak-config-"));
	return { configDir, nested, root };
}

test("files are ordered global first, then from the git root down to the cwd", async () => {
	// Arrange
	const { configDir, nested, root } = await repo();
	await writeFile(join(configDir, "AGENTS.md"), "global");
	await writeFile(join(root, "AGENTS.md"), "root");
	await writeFile(join(nested, "AGENTS.md"), "nested");

	// Act
	const files = await discoverInstructions(nested, configDir);

	// Assert
	assert.deepEqual(
		files.map((file) => file.text),
		["global", "root", "nested"],
	);
});

test("AGENTS.md wins over CLAUDE.md in the same directory, and CLAUDE.md is used alone", async () => {
	// Arrange
	const { configDir, nested, root } = await repo();
	await writeFile(join(root, "AGENTS.md"), "agents");
	await writeFile(join(root, "CLAUDE.md"), "claude");
	await writeFile(join(nested, "CLAUDE.md"), "only claude");

	// Act
	const files = await discoverInstructions(nested, configDir);

	// Assert
	assert.deepEqual(
		files.map((file) => file.text),
		["agents", "only claude"],
	);
});

test("without a git root only the cwd is searched, and missing or blank files are skipped", async () => {
	// Arrange
	const parent = await mkdtemp(join(tmpdir(), "sak-nogit-"));
	const cwd = join(parent, "child");
	await mkdir(cwd);
	await writeFile(join(parent, "AGENTS.md"), "parent");
	await writeFile(join(cwd, "CLAUDE.md"), "   \n");
	const configDir = join(parent, "missing");

	// Act
	const files = await discoverInstructions(cwd, configDir);

	// Assert
	assert.deepEqual(files, []);
	assert.equal(renderInstructions(files), undefined);
});

test("a file over the limit is truncated with a marker", async () => {
	// Arrange
	const { configDir, root } = await repo();
	await writeFile(join(root, "AGENTS.md"), "x".repeat(MAX_FILE_CHARS + 5));

	// Act
	const [file] = await discoverInstructions(root, configDir);

	// Assert
	assert.match(file?.text ?? "", /… truncated \(5 more characters\)$/);
});

test("a configured limit replaces the default when truncating", async () => {
	// Arrange
	const { configDir, root } = await repo();
	await writeFile(join(root, "AGENTS.md"), "abcdefghij");

	// Act
	const [file] = await discoverInstructions(root, configDir, 4);

	// Assert
	assert.match(file?.text ?? "", /^abcd\n… truncated \(6 more characters\)$/);
});

test("rendering wraps every file with its path inside one project_instructions tag", () => {
	// Arrange
	const files = [{ path: "/a/AGENTS.md", text: "alpha" }];

	// Act
	const text = renderInstructions(files);

	// Assert
	assert.match(text ?? "", /^<project_instructions>/);
	assert.match(text ?? "", /<instructions path="\/a\/AGENTS\.md">\nalpha\n<\/instructions>/);
	assert.match(text ?? "", /<\/project_instructions>$/);
});
