import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { findPersona, loadPersonas, parsePersona } from "../src/personas.ts";

const BUILDER = `---
name: builder
description: Use to implement an already-planned change.
color: green
permissionMode: default
model: sonnet
tools: Read, Edit, Write, Grep, Glob, Bash(mix compile:*), Bash(git diff:*), Skill(critical-review)
skills:
  - critical-review
---

You implement exactly what's specified.
`;

test("a Claude agent file maps to a persona with Pi tools, always including codemode", () => {
	// Arrange
	const file = BUILDER;

	// Act
	const persona = parsePersona("builder.md", file);

	// Assert
	assert.equal(persona.name, "builder");
	assert.equal(persona.description, "Use to implement an already-planned change.");
	assert.equal(persona.instructions, "You implement exactly what's specified.");
	assert.equal(persona.model, null);
	assert.deepEqual([...(persona.tools ?? [])].sort(), ["bash", "codemode", "edit", "read", "write"]);
	assert.deepEqual(persona.warnings, ["unsupported tool Skill(critical-review)"]);
});

test("a file without frontmatter is all instructions, named after the file, with every tool", () => {
	// Arrange
	const file = "Be terse.\n";

	// Act
	const persona = parsePersona("terse.md", file);

	// Assert
	assert.equal(persona.name, "terse");
	assert.equal(persona.instructions, "Be terse.");
	assert.equal(persona.tools, null);
});

test("a concrete model id in the file is kept while Claude aliases are dropped", () => {
	// Arrange
	const concrete = "---\nmodel: qwen3.8-27b-mlx\n---\nHi";
	const alias = "---\nmodel: opus\n---\nHi";

	// Act
	const results = [parsePersona("a.md", concrete).model, parsePersona("b.md", alias).model];

	// Assert
	assert.deepEqual(results, ["qwen3.8-27b-mlx", null]);
});

test("loading lists the built-in default first, then the files by name", async () => {
	// Arrange
	const directory = await mkdtemp(join(tmpdir(), "sak-personas-"));
	await writeFile(join(directory, "zeta.md"), "---\nname: zeta\n---\nZ");
	await writeFile(join(directory, "alpha.md"), "---\nname: alpha\n---\nA");
	await writeFile(join(directory, "notes.txt"), "ignored");

	// Act
	const personas = await loadPersonas(directory);

	// Assert
	assert.deepEqual(
		personas.map((persona) => [persona.name, persona.source]),
		[
			["default", "builtin"],
			["alpha", "file"],
			["zeta", "file"],
		],
	);
	assert.equal(personas[0]?.tools, null);
	assert.match(personas[0]?.instructions ?? "", /expert coding assistant/);
});

test("a file named default replaces the built-in one and a missing directory is fine", async () => {
	// Arrange
	const directory = await mkdtemp(join(tmpdir(), "sak-personas-"));
	await writeFile(join(directory, "default.md"), "---\nname: default\n---\nMine");

	// Act
	const overridden = await loadPersonas(directory);
	const missing = await loadPersonas(join(directory, "nope"));

	// Assert
	assert.deepEqual(overridden.map((persona) => [persona.name, persona.source, persona.instructions]), [["default", "file", "Mine"]]);
	assert.deepEqual(missing.map((persona) => persona.name), ["default"]);
});

test("finding an unknown persona fails", async () => {
	// Arrange
	const directory = await mkdtemp(join(tmpdir(), "sak-personas-"));

	// Act
	const result = findPersona(directory, "ghost");

	// Assert
	await assert.rejects(result, /unknown persona ghost/);
});
