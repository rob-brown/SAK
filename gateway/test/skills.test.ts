import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { discoverSkills, MAX_DESCRIPTION_CHARS, parseSkill, renderSkills } from "../src/skills.ts";

async function writeSkill(root: string, folder: string, frontmatter: string) {
	const directory = join(root, folder);
	await mkdir(directory, { recursive: true });
	await writeFile(join(directory, "SKILL.md"), `---\n${frontmatter}\n---\nBody`);
}

async function workspace() {
	const root = await mkdtemp(join(tmpdir(), "sak-skills-"));
	await mkdir(join(root, ".git"));
	const nested = join(root, "packages", "app");
	await mkdir(nested, { recursive: true });
	const configDir = await mkdtemp(join(tmpdir(), "sak-config-"));
	return { configDir, nested, root };
}

test("skills are found globally and from the git root down, and the nearer one wins a name clash", async () => {
	// Arrange
	const { configDir, nested, root } = await workspace();
	await writeSkill(join(configDir, "skills"), "alpha", "name: alpha\ndescription: global alpha");
	await writeSkill(join(root, ".agents", "skills"), "alpha", "name: alpha\ndescription: root alpha");
	await writeSkill(join(nested, ".agents", "skills"), "beta", "name: beta\ndescription: nested beta");

	// Act
	const { skills, warnings } = await discoverSkills(nested, configDir);

	// Assert
	assert.deepEqual(
		skills.map((skill) => [skill.name, skill.description]),
		[
			["alpha", "root alpha"],
			["beta", "nested beta"],
		],
	);
	assert.deepEqual(warnings, []);
});

test("an invalid skill is skipped with a warning and does not hide the valid ones", async () => {
	// Arrange
	const { configDir, root } = await workspace();
	const skillsDir = join(root, ".agents", "skills");
	await writeSkill(skillsDir, "good", "name: good\ndescription: works");
	await writeSkill(skillsDir, "bad-name", "name: Bad_Name\ndescription: nope");
	await writeSkill(skillsDir, "no-description", "name: no-description");
	await writeSkill(skillsDir, "folded", "name: folded\ndescription: >");

	// Act
	const { skills, warnings } = await discoverSkills(root, configDir);

	// Assert
	assert.deepEqual(
		skills.map((skill) => skill.name),
		["good"],
	);
	assert.equal(warnings.length, 3);
});

test("quotes around frontmatter values are removed and an oversized description is rejected", () => {
	// Arrange
	const quoted = '---\nname: "quoted"\ndescription: \'with quotes\'\n---\n';
	const oversized = `---\nname: big\ndescription: ${"x".repeat(MAX_DESCRIPTION_CHARS + 1)}\n---\n`;

	// Act
	const first = parseSkill("a/SKILL.md", quoted);
	const second = parseSkill("b/SKILL.md", oversized);

	// Assert
	assert.deepEqual(first, {
		skill: { name: "quoted", description: "with quotes", path: "a/SKILL.md", arguments: [] },
		warning: null,
	});
	assert.ok("warning" in second);
});

test("rendering lists each skill with its location, escapes markup, and is empty without skills", () => {
	// Arrange
	const skills = [{ name: "pdf", description: 'Fill <forms> & "more"', path: "/s/pdf/SKILL.md", arguments: [] }];

	// Act
	const text = renderSkills(skills);

	// Assert
	assert.match(text ?? "", /^<skills>/);
	assert.match(text ?? "", /<skill name="pdf" location="\/s\/pdf\/SKILL\.md">Fill &lt;forms&gt; &amp; &quot;more&quot;<\/skill>/);
	assert.equal(renderSkills([]), undefined);
});
