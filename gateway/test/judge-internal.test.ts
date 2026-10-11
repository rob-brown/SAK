import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { JudgeClient } from "../src/judge/client.ts";
import { suggestSkill } from "../src/judge/suggest.ts";
import { choiceAnswers, fakeServer, type Handler } from "./fake-judge.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;
type Message = { role: string; content: unknown; toolsAdded?: { name: string }[] };

function client(url: string) {
	return new JudgeClient({ baseUrl: url, model: "winnow:e4b", timeoutMs: 5000 });
}

function lastUserText(messages: Message[]): string {
	const user = [...messages].reverse().find((message) => message.role === "user");
	return typeof user?.content === "string" ? user.content : "";
}

async function withReader(harness: Harness) {
	await writeFile(
		join(harness.personasDir, "reader.md"),
		"---\nname: reader\ndescription: Reads and summarises files, never edits\ntools: Read\n---\nOnly read.",
	);
}

async function delegate(harness: Harness, args: Record<string, string | string[]>) {
	const toolsByPrompt = new Map<string, string[]>();
	const child = (context: { messages: Message[] }) => {
		const head = context.messages.find((message) => message.role === "system");
		toolsByPrompt.set(lastUserText(context.messages), (head?.toolsAdded ?? []).map((tool) => tool.name).sort());
		return fauxAssistantMessage("ok");
	};
	const prompts = args.prompts as string[];
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("agent", args), { stopReason: "toolUse" }),
		...prompts.map(() => child),
		fauxAssistantMessage("finished"),
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd: tmpdir() });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	return toolsByPrompt;
}

const READER_TOOLS = ["codemode", "read"];
const FULL_TOOLS = ["bash", "codemode", "edit", "judge", "read", "write"];

const picks: Handler = (seen) => {
	const ids = Object.keys(seen.body.questions);
	return { status: 200, body: choiceAnswers({ [ids[0] as string]: ["reader", 0.95], [ids[1] as string]: ["default", 0.9] }) };
};

test("each prompt gets the persona the judge picks for it, and the judge sees the persona descriptions", async () => {
	// Arrange
	const server = await fakeServer(picks);
	const harness = await setup(undefined, 6, client(server.url), { pickPersonas: true });
	await withReader(harness);

	// Act
	const tools = await delegate(harness, { prompts: ["summarise the docs", "fix the parser bug"] });

	// Assert
	assert.deepEqual(tools.get("summarise the docs"), READER_TOOLS);
	assert.deepEqual(tools.get("fix the parser bug"), FULL_TOOLS);
	assert.equal(server.seen.length, 1);
	assert.deepEqual(server.seen[0]?.body.state, { tasks: ["summarise the docs", "fix the parser bug"] });
	const options = server.seen[0]?.body.questions.t0.criteria;
	assert.equal(options.reader, "Reads and summarises files, never edits");
	assert.ok("default" in options);
	await harness.close();
	await server.close();
});

test("an unsure judge, a failing judge, an explicit persona and a single persona all use the default or the named one", async () => {
	// Arrange
	const unsure = await fakeServer((seen) => ({
		status: 200,
		body: choiceAnswers({ t0: ["reader", 0.5], ...(seen.body.questions.t1 ? { t1: ["reader", 0.79] } : {}) }),
	}));
	const failing = await fakeServer(() => ({ status: 500, body: "boom" }));
	const explicit = await fakeServer(picks);
	const alone = await fakeServer(picks);
	const harnesses = [
		await setup(undefined, 6, client(unsure.url), { pickPersonas: true }),
		await setup(undefined, 6, client(failing.url), { pickPersonas: true }),
		await setup(undefined, 6, client(explicit.url), { pickPersonas: true }),
		await setup(undefined, 6, client(alone.url), { pickPersonas: true }),
	];
	for (const harness of harnesses.slice(0, 3)) await withReader(harness);

	// Act
	const lowConfidence = await delegate(harnesses[0] as Harness, { prompts: ["a", "b"] });
	const broken = await delegate(harnesses[1] as Harness, { prompts: ["a"] });
	const named = await delegate(harnesses[2] as Harness, { prompts: ["a"], persona: "reader" });
	const single = await delegate(harnesses[3] as Harness, { prompts: ["a"] });

	// Assert
	assert.deepEqual([lowConfidence.get("a"), lowConfidence.get("b")], [FULL_TOOLS, FULL_TOOLS]);
	assert.deepEqual(broken.get("a"), FULL_TOOLS);
	assert.deepEqual(named.get("a"), READER_TOOLS);
	assert.equal(explicit.seen.length, 0);
	assert.equal(alone.seen.length, 0);
	await Promise.all(harnesses.map((harness) => harness.close()));
	await Promise.all([unsure, failing, explicit, alone].map((server) => server.close()));
});

test("without the pick_personas setting the judge is not consulted", async () => {
	// Arrange
	const server = await fakeServer(picks);
	const harness = await setup(undefined, 6, client(server.url), { pickPersonas: false });
	await withReader(harness);

	// Act
	const tools = await delegate(harness, { prompts: ["summarise the docs"] });

	// Assert
	assert.deepEqual(tools.get("summarise the docs"), FULL_TOOLS);
	assert.equal(server.seen.length, 0);
	await harness.close();
	await server.close();
});

async function project(withSkill = true) {
	const directory = await mkdtemp(join(tmpdir(), "sak-suggest-"));
	if (withSkill) {
		const skill = join(directory, ".agents", "skills", "pdf");
		await mkdir(skill, { recursive: true });
		await writeFile(join(skill, "SKILL.md"), "---\nname: pdf\ndescription: Fill in, merge and extract text from PDF forms and documents\n---\nBody");
	}
	return directory;
}

async function submitted(harness: Harness, cwd: string, content: string, persona?: string) {
	harness.faux.setResponses([fauxAssistantMessage("ok")]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd, ...(persona ? { persona } : {}) });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	const entry = harness.outgoing
		.filter((message) => message.type === "events")
		.flatMap((message) => (message as { events: { type: string; entry?: { kind: string; model: { content: string }[] } }[] }).events)
		.find((event) => event.type === "message_end" && event.entry?.kind === "pi.user");
	return entry?.entry?.model[0]?.content;
}

const REQUEST = "please fill in this PDF form for me";

test("a confident skill match is put in front of the message, with the skills as the judge's options", async () => {
	// Arrange
	const server = await fakeServer(() => ({ status: 200, body: choiceAnswers({ skill: ["pdf", 0.93] }) }));
	const harness = await setup(undefined, undefined, client(server.url), { suggestSkills: true });

	// Act
	const content = await submitted(harness, await project(), REQUEST);

	// Assert
	assert.match(content ?? "", /^<skill-suggestion name="pdf" confidence="0\.93">.*"pdf" skill.*<\/skill-suggestion>\n\n/);
	assert.ok((content ?? "").endsWith(`\n\n${REQUEST}`));
	assert.equal(server.seen[0]?.body.state, REQUEST);
	assert.deepEqual(Object.keys(server.seen[0]?.body.questions.skill.criteria), ["none", "pdf"]);
	await harness.close();
	await server.close();
});

test("the message is sent as typed when the judge says none, is unsure, is down, or the message is short", async () => {
	// Arrange
	const cases = [
		await fakeServer(() => ({ status: 200, body: choiceAnswers({ skill: ["none", 0.99] }) })),
		await fakeServer(() => ({ status: 200, body: choiceAnswers({ skill: ["pdf", 0.5] }) })),
		await fakeServer(() => ({ status: 503, body: "down" })),
		await fakeServer(() => ({ status: 200, body: choiceAnswers({ skill: ["pdf", 0.99] }) })),
	];
	const harnesses = await Promise.all(cases.map((server) => setup(undefined, undefined, client(server.url), { suggestSkills: true })));

	// Act
	const sent = [
		await submitted(harnesses[0] as Harness, await project(), REQUEST),
		await submitted(harnesses[1] as Harness, await project(), REQUEST),
		await submitted(harnesses[2] as Harness, await project(), REQUEST),
		await submitted(harnesses[3] as Harness, await project(), "hi"),
	];

	// Assert
	assert.deepEqual(sent, [REQUEST, REQUEST, REQUEST, "hi"]);
	assert.equal(cases[3]?.seen.length, 0);
	await Promise.all(harnesses.map((harness) => harness.close()));
	await Promise.all(cases.map((server) => server.close()));
});

test("no request is made when there are no skills, or the persona cannot read files, or the setting is off", async () => {
	// Arrange
	const server = await fakeServer(() => ({ status: 200, body: choiceAnswers({ skill: ["pdf", 0.99] }) }));
	const on = await setup(undefined, undefined, client(server.url), { suggestSkills: true });
	await writeFile(join(on.personasDir, "shell.md"), "---\nname: shell\ntools: Bash\n---\nShell only.");
	const off = await setup(undefined, undefined, client(server.url), { suggestSkills: false });

	// Act
	const noSkills = await submitted(on, await project(false), REQUEST);
	const cannotRead = await submitted(await setupShell(server.url), await project(), REQUEST, "shell");
	const disabled = await submitted(off, await project(), REQUEST);

	// Assert
	assert.deepEqual([noSkills, cannotRead, disabled], [REQUEST, REQUEST, REQUEST]);
	assert.equal(server.seen.length, 0);
	await on.close();
	await off.close();
	await server.close();
});

type Note = { purpose: string; outcome: string; acted: boolean; model: string; probability: number | null; detail: string | null };

async function notesOf(harness: Harness): Promise<Note[]> {
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: `again-${Math.random()}`, type: "attach", conversationId });
	const snapshot = harness.outgoing.filter((message) => message.type === "snapshot").pop() as {
		snapshot: { entries: { kind: string; data?: Note; model?: unknown }[] };
	};
	return snapshot.snapshot.entries.filter((entry) => entry.kind === "sak.judge").map((entry) => entry.data as Note);
}

test("every skill check that reaches the judge leaves a note in the history, and the model never sees it", async () => {
	// Arrange
	const answers = [["pdf", 0.93], ["none", 0.97]] as const;
	const server = await fakeServer((_seen, count) => ({ status: 200, body: choiceAnswers({ skill: [...(answers[count - 1] as readonly [string, number])] }) }));
	const harness = await setup(undefined, undefined, client(server.url), { suggestSkills: true });
	const cwd = await project();
	const requests: string[] = [];
	harness.faux.setResponses([
		(context: { messages: Message[] }) => {
			requests.push(JSON.stringify(context.messages));
			return fauxAssistantMessage("first");
		},
		(context: { messages: Message[] }) => {
			requests.push(JSON.stringify(context.messages));
			return fauxAssistantMessage("second");
		},
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });

	// Act
	await harness.gateway.handle({ id: "s1", type: "submit", conversationId, content: REQUEST });
	await waitFor(() => requests.length === 1);
	await waitFor(() => harness.outgoing.filter((m) => JSON.stringify(m).includes("run_end")).length >= 1);
	await harness.gateway.handle({ id: "s2", type: "submit", conversationId, content: "tell me about the weather today" });
	await waitFor(() => requests.length === 2);
	const notes = await notesOf(harness);

	// Assert
	assert.deepEqual(notes.map((note) => [note.purpose, note.outcome, note.acted]), [
		["skill suggestion", "suggested pdf", true],
		["skill suggestion", "no skill fits", false],
	]);
	assert.equal(notes[0]?.model, "winnow:e4b");
	assert.equal(notes[0]?.probability, 0.93);
	assert.doesNotMatch(requests.join(""), /sak\.judge|suggested pdf|no skill fits/);
	await harness.close();
	await server.close();
});

test("a judge that is down is noted as unavailable, and a message that never reaches the judge leaves no note", async () => {
	// Arrange
	const server = await fakeServer(() => ({ status: 503, body: "down" }));
	const harness = await setup(undefined, undefined, client(server.url), { suggestSkills: true });

	// Act
	await submitted(harness, await project(), REQUEST);
	const down = await notesOf(harness);
	const quiet = await setup(undefined, undefined, client(server.url), { suggestSkills: true });
	await submitted(quiet, await project(), "hi");
	const none = await notesOf(quiet);

	// Assert
	assert.deepEqual(down.map((note) => [note.outcome, note.acted]), [["judge unavailable", false]]);
	assert.deepEqual(none, []);
	await harness.close();
	await quiet.close();
	await server.close();
});

test("a persona pick is noted on the conversation that made the agent call", async () => {
	// Arrange
	const server = await fakeServer(picks);
	const harness = await setup(undefined, 6, client(server.url), { pickPersonas: true });
	await withReader(harness);

	// Act
	await delegate(harness, { prompts: ["summarise the docs", "fix the parser bug"] });
	const notes = await notesOf(harness);

	// Assert
	assert.equal(notes.length, 1);
	assert.deepEqual([notes[0]?.purpose, notes[0]?.acted, notes[0]?.outcome], ["persona pick", true, "chose a persona for 1 of 2 prompts"]);
	assert.match(notes[0]?.detail ?? "", /1: reader \(95%\), 2: default \(90%\)/);
	await harness.close();
	await server.close();
});

const live = await fetch("http://localhost:11435/v1/models", { signal: AbortSignal.timeout(500) }).then(
	(response) => response.ok,
	() => false,
);

test("winnow:e4b matches a PDF request to the pdf skill and leaves an unrelated one alone", { skip: !live }, async () => {
	// Arrange
	const local = new JudgeClient({ baseUrl: "http://localhost:11435", model: "winnow:e4b", timeoutMs: 60_000 });
	const deps = { client: local, minConfidence: 0.7, configDir: await mkdtemp(join(tmpdir(), "sak-live-")) };
	const cwd = await project();

	// Act
	const pdf = (await suggestSkill(deps, "please fill in the attached PDF tax form", cwd)).content;
	const unrelated = (await suggestSkill(deps, "what is the capital of France, just curious", cwd)).note;

	// Assert
	assert.match(pdf ?? "", /^<skill-suggestion name="pdf"/);
	assert.equal(unrelated?.acted, false);
});

async function setupShell(url: string) {
	const harness = await setup(undefined, undefined, client(url), { suggestSkills: true });
	await writeFile(join(harness.personasDir, "shell.md"), "---\nname: shell\ntools: Bash\n---\nShell only.");
	return harness;
}
