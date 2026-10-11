import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MAX_ARGUMENTS, parseArguments } from "../src/skill-arguments.ts";
import { parseSkill } from "../src/skills.ts";
import { reply, setup } from "./support.ts";

test("a JSON list declares arguments with descriptions, defaults and required flags, and bare names are allowed", () => {
	// Arrange
	const fields = {
		arguments:
			'[{"name":"topic","description":"What to write about","required":true},{"name":"length","default":"short"},"tone"]',
	};

	// Act
	const parsed = parseArguments(fields);

	// Assert
	assert.equal(parsed.warning, null);
	assert.deepEqual(parsed.arguments, [
		{ name: "topic", description: "What to write about", default: null, required: true },
		{ name: "length", description: null, default: "short", required: false },
		{ name: "tone", description: null, default: null, required: false },
	]);
});

test("an argument-hint in the Claude style gives optional arguments in square brackets and required ones in angle brackets", () => {
	// Arrange
	const fields = { "argument-hint": "[topic] <length> [tone...]" };

	// Act
	const parsed = parseArguments(fields);

	// Assert
	assert.deepEqual(
		parsed.arguments.map((argument) => [argument.name, argument.required]),
		[
			["topic", false],
			["length", true],
			["tone", false],
		],
	);
});

test("a declared list wins over the hint, and a skill without either has no arguments", () => {
	// Arrange
	const both = { arguments: '["a"]', "argument-hint": "[b] [c]" };

	// Act
	const declared = parseArguments(both);
	const none = parseArguments({});

	// Assert
	assert.deepEqual(declared.arguments.map((argument) => argument.name), ["a"]);
	assert.deepEqual([none.arguments, none.warning], [[], null]);
});

test("malformed declarations give no arguments and a reason, without invalidating the skill", () => {
	// Arrange
	const many = JSON.stringify(Array.from({ length: MAX_ARGUMENTS + 1 }, (_, index) => `a${index}`));
	const bad = [
		{ arguments: "not json" },
		{ arguments: '{"name":"x"}' },
		{ arguments: '[{"name":"has space"}]' },
		{ arguments: '["same","SAME"]' },
		{ arguments: many },
	];

	// Act
	const results = bad.map(parseArguments);
	const skill = parseSkill("s/SKILL.md", "---\nname: pdf\ndescription: Forms\narguments: not json\n---\n");

	// Assert
	assert.ok(results.every((result) => result.arguments.length === 0 && result.warning !== null));
	assert.ok("skill" in skill && skill.skill.arguments.length === 0 && skill.warning?.includes("s/SKILL.md"));
});

async function project() {
	const directory = await mkdtemp(join(tmpdir(), "sak-skill-cmd-"));
	const skill = join(directory, ".agents", "skills", "report");
	await mkdir(skill, { recursive: true });
	await writeFile(
		join(skill, "SKILL.md"),
		'---\nname: report\ndescription: Write a status report\narguments: [{"name":"topic","required":true},"length"]\n---\nBody',
	);
	return directory;
}

test("list_skills returns the skills for the conversation's directory with their arguments", async () => {
	// Arrange
	const harness = await setup();
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: await project() });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;

	// Act
	await harness.gateway.handle({ id: "l", type: "list_skills", conversationId });

	// Assert
	const listed = reply(harness.outgoing, "l") as {
		result: { skills: { name: string; path: string; arguments: { name: string; required: boolean }[] }[] };
	};
	assert.equal(listed.result.skills.length, 1);
	assert.equal(listed.result.skills[0]?.name, "report");
	assert.match(listed.result.skills[0]?.path ?? "", /report\/SKILL\.md$/);
	assert.deepEqual(
		listed.result.skills[0]?.arguments.map((argument) => [argument.name, argument.required]),
		[
			["topic", true],
			["length", false],
		],
	);
	await harness.close();
});

test("list_skills is empty for a persona that cannot read files, and an unknown conversation is an error", async () => {
	// Arrange
	const harness = await setup();
	await writeFile(join(harness.personasDir, "shell.md"), "---\nname: shell\ntools: Bash\n---\nShell only.");
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: await project(), persona: "shell" });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;

	// Act
	await harness.gateway.handle({ id: "l", type: "list_skills", conversationId });
	await harness.gateway.handle({ id: "u", type: "list_skills", conversationId: 9999 });

	// Assert
	assert.deepEqual((reply(harness.outgoing, "l") as { result: unknown }).result, { skills: [] });
	assert.equal((reply(harness.outgoing, "u") as { ok: boolean }).ok, false);
	await harness.close();
});
