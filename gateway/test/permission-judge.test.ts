import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { access, mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { JudgeClient } from "../src/judge/client.ts";
import { DEFAULT_THRESHOLD, PermissionJudge } from "../src/permissions/judge.ts";
import { type Mode, parseRule, type Policy } from "../src/permissions/rules.ts";
import type { Outgoing } from "../src/protocol.ts";
import { fakeServer } from "./fake-judge.ts";
import { repo } from "./repo.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

type Harness = Awaited<ReturnType<typeof setup>>;
type Request = Extract<Outgoing, { type: "permission_request" }>;

function fraction(value: number) {
	return scored(value * 3);
}

function scored(score: unknown) {
	return { status: 200, body: { model: "m", answers: { destructive: { type: "score", score } } } };
}

function policy(mode: Mode, rules: { allow?: string[]; ask?: string[]; judge?: string[] } = {}): Policy {
	return {
		mode,
		allow: (rules.allow ?? []).map(parseRule),
		ask: (rules.ask ?? []).map(parseRule),
		deny: [],
		judge: (rules.judge ?? ["Bash"]).map(parseRule),
	};
}

function requests(outgoing: Outgoing[]) {
	return outgoing.filter((message): message is Request => message.type === "permission_request");
}

async function exists(path: string) {
	return access(path).then(
		() => true,
		() => false,
	);
}

async function boot(url: string, rules: Policy, withJudge = true) {
	const judge = withJudge ? new PermissionJudge(new JudgeClient({ baseUrl: url, model: "m", timeoutMs: 3000 }), DEFAULT_THRESHOLD) : undefined;
	return setup(rules, undefined, undefined, undefined, judge);
}

async function runCommand(harness: Harness, cwd: string, command: string, mode?: Mode) {
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("bash", { command }), { stopReason: "toolUse" }),
		fauxAssistantMessage("done"),
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation", cwd });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	if (mode) await harness.gateway.handle({ id: "m", type: "permission_mode", conversationId, mode });
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => requests(harness.outgoing).length > 0 || hasEvent(harness.outgoing, "run_end"));
	return conversationId;
}

async function finish(harness: Harness, conversationId: number, approval: "allow" | "deny") {
	const request = requests(harness.outgoing)[0] as Request;
	await harness.gateway.handle({ id: "r", type: "permission_reply", requestId: request.requestId, approval });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	await harness.gateway.handle({ id: "again", type: "attach", conversationId });
}

type Note = { purpose: string; outcome: string; acted: boolean; probability: number | null };

function notes(harness: Harness): Note[] {
	const snapshot = harness.outgoing.filter((message) => message.type === "snapshot").pop() as {
		snapshot: { entries: { kind: string; data?: Note }[] };
	};
	return snapshot.snapshot.entries.filter((entry) => entry.kind === "sak.judge").map((entry) => entry.data as Note);
}

async function marker() {
	return join(await mkdtemp(join(tmpdir(), "sak-pj-")), "ran");
}

test("a score of 1.5 out of 3 or more is flagged by default, scores outside the scale are clamped", async () => {
	// Arrange
	const scores = [0, 1, 1.4, 1.5, 2, 3, 7, -1];
	let next = 0;
	const server = await fakeServer(() => scored(scores[next++]));
	const judge = new PermissionJudge(new JudgeClient({ baseUrl: server.url, model: "m", timeoutMs: 3000 }), DEFAULT_THRESHOLD);

	// Act
	const flagged: boolean[] = [];
	for (const _ of scores) {
		flagged.push((await judge.assess({ name: "bash", arguments: { command: "echo hi" } }, tmpdir())).flagged);
	}

	// Assert
	assert.deepEqual(flagged, [false, false, false, true, true, true, true, false]);
	await server.close();
});

test("an answer without a numeric score is treated as the judge being unavailable", async () => {
	// Arrange
	const answers = [undefined, "3", null];
	let next = 0;
	const server = await fakeServer(() => scored(answers[next++]));
	const judge = new PermissionJudge(new JudgeClient({ baseUrl: server.url, model: "m", timeoutMs: 3000 }), DEFAULT_THRESHOLD);

	// Act
	const assessed = [];
	for (const _ of answers) {
		assessed.push(await judge.assess({ name: "bash", arguments: { command: "echo hi" } }, tmpdir()));
	}

	// Assert
	assert.deepEqual(assessed.map((result) => result.flagged), [true, true, true]);
	assert.deepEqual(
		assessed.map((result) => result.note?.outcome),
		Array(3).fill("judge unavailable, asked a person"),
	);
	await server.close();
});

test("a command the judge flags as destructive goes to a person with the reason, even in auto mode", async () => {
	// Arrange
	const server = await fakeServer(() => fraction(0.97));
	const harness = await boot(server.url, policy("auto"));
	const file = await marker();

	// Act
	const id = await runCommand(harness, tmpdir(), `touch ${file}`);
	const asked = requests(harness.outgoing)[0];
	await finish(harness, id, "deny");

	// Assert
	assert.equal(asked?.summary, `touch ${file}`);
	assert.equal(asked?.note, "Flagged by the judge as likely destructive (97%).");
	assert.equal(await exists(file), false);
	assert.deepEqual(notes(harness).map((note) => [note.purpose, note.outcome, note.acted, note.probability]), [
		["permission", "flagged as likely destructive", true, 0.97],
	]);
	assert.equal(server.seen[0]?.body.state.command, `touch ${file}`);
	await harness.close();
	await server.close();
});

test("a command the judge finds safe runs in auto mode without a prompt, and still asks in ask mode", async () => {
	// Arrange
	const server = await fakeServer(() => fraction(0.04));
	const auto = await boot(server.url, policy("auto"));
	const careful = await boot(server.url, policy("ask"));
	const ran = await marker();
	const other = await marker();

	// Act
	const autoId = await runCommand(auto, tmpdir(), `touch ${ran}`);
	await auto.gateway.handle({ id: "again", type: "attach", conversationId: autoId });
	const carefulId = await runCommand(careful, tmpdir(), `touch ${other}`);
	const asked = requests(careful.outgoing)[0];
	await finish(careful, carefulId, "deny");

	// Assert
	assert.equal(await exists(ran), true);
	assert.equal(requests(auto.outgoing).length, 0);
	assert.deepEqual(notes(auto).map((note) => [note.outcome, note.acted]), [["looks safe to run", false]]);
	assert.equal(asked?.note, undefined);
	assert.equal(await exists(other), false);
	await auto.close();
	await careful.close();
	await server.close();
});

test("ask and allow rules decide before the judge is consulted", async () => {
	// Arrange
	const server = await fakeServer(() => fraction(0.99));
	const asking = await boot(server.url, policy("auto", { ask: ["Bash(touch *)"] }));
	const allowing = await boot(server.url, policy("ask", { allow: ["Bash(touch *)"] }));
	const first = await marker();
	const second = await marker();

	// Act
	const askingId = await runCommand(asking, tmpdir(), `touch ${first}`);
	const asked = requests(asking.outgoing)[0];
	await finish(asking, askingId, "allow");
	await runCommand(allowing, tmpdir(), `touch ${second}`);
	await waitFor(() => hasEvent(allowing.outgoing, "run_end"));

	// Assert
	assert.equal(server.seen.length, 0);
	assert.equal(asked?.note, undefined);
	assert.equal(await exists(first), true);
	assert.equal(await exists(second), true);
	assert.equal(requests(allowing.outgoing).length, 0);
	await asking.close();
	await allowing.close();
	await server.close();
});

test("when the judge cannot be reached, or is not enabled, a person decides", async () => {
	// Arrange
	const down = await fakeServer(() => ({ status: 503, body: "down" }));
	const unreachable = await boot(down.url, policy("auto"));
	const disabled = await boot(down.url, policy("auto"), false);

	// Act
	const firstId = await runCommand(unreachable, tmpdir(), "echo hi");
	const first = requests(unreachable.outgoing)[0];
	await finish(unreachable, firstId, "deny");
	const secondId = await runCommand(disabled, tmpdir(), "echo hi");
	const second = requests(disabled.outgoing)[0];
	await finish(disabled, secondId, "deny");

	// Assert
	assert.equal(first?.note, "The judge could not be reached, so this needs your decision.");
	assert.equal(second?.note, "No judge is available, so this needs your decision.");
	assert.deepEqual(notes(unreachable).map((note) => [note.outcome, note.acted]), [["judge unavailable, asked a person", true]]);
	await unreachable.close();
	await disabled.close();
	await down.close();
});

test("removing a git-ignored build directory runs without asking the judge, while removing tracked work is flagged", async () => {
	// Arrange
	const server = await fakeServer((seen) => fraction(JSON.stringify(seen.body.state.facts).includes("src is tracked") ? 0.98 : 0.05));
	const harness = await boot(server.url, policy("auto"));
	const other = await boot(server.url, policy("auto"));
	const directory = await mkdtemp(join(tmpdir(), "sak-pj-repo-"));
	const git = (...args: string[]) =>
		execFileSync("git", ["-C", directory, "-c", "user.email=t@t", "-c", "user.name=t", ...args], { stdio: "ignore" });
	git("init", "-q");
	await mkdir(join(directory, "build"));
	await mkdir(join(directory, "src"));
	await writeFile(join(directory, ".gitignore"), "build/\n");
	await writeFile(join(directory, "src", "a.ts"), "x\n");
	await writeFile(join(directory, "build", "o.js"), "y\n");
	git("add", ".gitignore", "src");
	git("commit", "-q", "-m", "init");
	await writeFile(join(directory, "src", "a.ts"), "changed\n");

	// Act
	const id = await runCommand(harness, directory, "rm -rf build");
	await harness.gateway.handle({ id: "again", type: "attach", conversationId: id });
	const flaggedId = await runCommand(other, directory, "rm -rf src");
	const flagged = requests(other.outgoing)[0];
	await finish(other, flaggedId, "deny");

	// Assert
	assert.equal(await exists(join(directory, "build")), false);
	assert.equal(requests(harness.outgoing).length, 0);
	assert.deepEqual(notes(harness).map((note) => note.outcome), ["only git-ignored files inside the project"]);
	assert.equal(server.seen.length, 1);
	assert.equal(flagged?.note, "Flagged by the judge as likely destructive (98%).");
	assert.equal(await exists(join(directory, "src")), true);
	await harness.close();
	await other.close();
	await server.close();
});

const cygnet = await fetch("http://localhost:11435/v1/models", { signal: AbortSignal.timeout(500) }).then(
	async (response) => ((await response.json()) as { models: { name: string }[] }).models.some((model) => model.name === "cygnet:latest"),
	() => false,
);

test("cygnet flags removing uncommitted work and leaves a status check and an ignored build directory alone", { skip: !cygnet }, async () => {
	// Arrange
	const directory = await repo();
	await writeFile(join(directory, "src", "a.ts"), "export const a = 2;\n");
	const client = new JudgeClient({ baseUrl: "http://localhost:11435", model: "cygnet:latest", timeoutMs: 120_000 });
	const judge = new PermissionJudge(client, DEFAULT_THRESHOLD);
	const assess = (command: string) => judge.assess({ name: "bash", arguments: { command } }, directory);

	// Act
	const removal = await assess("rm -rf src");
	const status = await assess("git status");
	const build = await assess("rm -rf build");

	// Assert
	assert.equal(removal.flagged, true);
	assert.equal(status.flagged, false);
	assert.equal(build.flagged, false);
	assert.match(build.note?.outcome ?? "", /only git-ignored files/);
});
