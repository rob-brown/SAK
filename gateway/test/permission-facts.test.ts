import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { gatherFacts, targetsOf } from "../src/permissions/facts.ts";
import { repo } from "./repo.ts";

test("targets are the non-flag words after rm, honouring quotes and a -- separator", () => {
	// Arrange
	const segments = ["rm -rf build 'my dir' dist", "rm -- -weird.txt", "rm"];

	// Act
	const targets = segments.map(targetsOf);

	// Assert
	assert.deepEqual(targets, [["build", "my dir", "dist"], ["-weird.txt"], []]);
});

test("removing only git-ignored files inside the project is recognised and described", async () => {
	// Arrange
	const directory = await repo();

	// Act
	const facts = await gatherFacts("rm -rf build", directory);

	// Assert
	assert.equal(facts.onlyIgnoredTargets, true);
	assert.match(facts.lines.join("\n"), /build is ignored by git/);
	assert.match(facts.lines[0] ?? "", /uncommitted changes/);
});

test("anything else that is removed is described by what git knows and is not exempt", async () => {
	// Arrange
	const directory = await repo();
	await writeFile(join(directory, "src", "a.ts"), "export const a = 2;\n");

	// Act
	const dirty = await gatherFacts("rm -rf src", directory);
	const untracked = await gatherFacts("rm notes.txt", directory);
	const mixed = await gatherFacts("rm -rf build src", directory);
	const outside = await gatherFacts("rm -rf /tmp/elsewhere", directory);
	const missing = await gatherFacts("rm -rf nothing-here", directory);

	// Assert
	assert.match(dirty.lines.join("\n"), /src is tracked by git and has uncommitted changes/);
	assert.match(untracked.lines.join("\n"), /notes\.txt is untracked and not ignored/);
	assert.deepEqual(
		[dirty, untracked, mixed, outside, missing].map((facts) => facts.onlyIgnoredTargets),
		[false, false, false, false, false],
	);
	assert.match(outside.lines.join("\n"), /\/tmp\/elsewhere is outside the project/);
	assert.match(missing.lines.join("\n"), /nothing-here does not exist/);
});

test("the exemption needs every part to be a removal of ignored files and never covers the project itself", async () => {
	// Arrange
	const directory = await repo();

	// Act
	const chained = await gatherFacts("rm -rf build && echo done", directory);
	const substitution = await gatherFacts("rm -rf build $(echo src)", directory);
	const everything = await gatherFacts("rm -rf .", directory);
	const plain = await gatherFacts("git status", directory);

	// Assert
	assert.deepEqual(
		[chained, substitution, everything, plain].map((facts) => facts.onlyIgnoredTargets),
		[false, false, false, false],
	);
	assert.equal(plain.lines.length, 1);
});

test("outside a repository the facts say so and nothing is exempt", async () => {
	// Arrange
	const directory = await mkdtemp(join(tmpdir(), "sak-nogit-"));
	await mkdir(join(directory, "build"));

	// Act
	const facts = await gatherFacts("rm -rf build", directory);

	// Assert
	assert.equal(facts.onlyIgnoredTargets, false);
	assert.match(facts.lines[0] ?? "", /not in a git repository/);
	assert.match(facts.lines.join("\n"), /build is not under version control/);
});
