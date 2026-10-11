import { execFile } from "node:child_process";
import { stat } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";
import { promisify } from "node:util";
import { parseCommand } from "./command.ts";

const run = promisify(execFile);
const GIT_TIMEOUT_MS = 3000;

export type Facts = {
	readonly lines: readonly string[];
	readonly onlyIgnoredTargets: boolean;
};

type Tracking = "ignored" | "not a repository" | "tracked clean" | "tracked dirty" | "untracked";

export async function gatherFacts(command: string, cwd: string): Promise<Facts> {
	const parsed = parseCommand(command);
	const removals = parsed.segments.filter(isRemoval);
	const targets = removals.flatMap(targetsOf).map((target) => resolve(cwd, target));
	const lines = [await repositoryState(cwd)];
	const states: Tracking[] = [];
	for (const target of targets) {
		const state = await trackingOf(target, cwd);
		states.push(state);
		lines.push(await describe(target, cwd, state));
	}
	const onlyIgnoredTargets =
		!parsed.opaque &&
		parsed.segments.length > 0 &&
		removals.length === parsed.segments.length &&
		targets.length > 0 &&
		targets.every(
			(target, index) => states[index] === "ignored" && isInside(cwd, target) && resolve(cwd) !== target,
		);
	return { lines, onlyIgnoredTargets };
}

export function targetsOf(segment: string): string[] {
	const words = tokenise(segment).slice(1);
	const end = words.indexOf("--");
	const flagless = end === -1 ? words.filter((word) => !word.startsWith("-")) : words.slice(end + 1);
	return flagless.filter((word) => word !== "");
}

function isRemoval(segment: string): boolean {
	return tokenise(segment)[0] === "rm";
}

function tokenise(segment: string): string[] {
	const words: string[] = [];
	let current = "";
	let quote: string | undefined;
	for (const char of segment) {
		if (quote !== undefined) {
			if (char === quote) quote = undefined;
			else current += char;
		} else if (char === "'" || char === '"') {
			quote = char;
		} else if (/\s/.test(char)) {
			if (current !== "") words.push(current);
			current = "";
		} else {
			current += char;
		}
	}
	if (current !== "") words.push(current);
	return words;
}

async function repositoryState(cwd: string): Promise<string> {
	const status = await git(cwd, ["status", "--porcelain"]);
	if (status === undefined) return "the working directory is not in a git repository";
	return status.stdout.trim() === ""
		? "the working tree is clean, everything is committed"
		: "the working tree has uncommitted changes";
}

async function trackingOf(target: string, cwd: string): Promise<Tracking> {
	if ((await git(cwd, ["rev-parse", "--is-inside-work-tree"])) === undefined) return "not a repository";
	if ((await git(cwd, ["check-ignore", "-q", "--", target]))?.code === 0) return "ignored";
	const tracked = await git(cwd, ["ls-files", "--error-unmatch", "--", target]);
	if (tracked?.code !== 0) return "untracked";
	const changes = await git(cwd, ["status", "--porcelain", "--", target]);
	return changes !== undefined && changes.stdout.trim() !== "" ? "tracked dirty" : "tracked clean";
}

async function describe(target: string, cwd: string, state: Tracking): Promise<string> {
	const name = isInside(cwd, target) ? relative(cwd, target) || "." : target;
	if (!isInside(cwd, target)) return `${name} is outside the project`;
	const exists = await stat(target).then(
		() => true,
		() => false,
	);
	if (!exists) return `${name} does not exist`;
	const text: Record<Tracking, string> = {
		ignored: "is ignored by git, so it is not part of the committed work",
		"not a repository": "is not under version control",
		"tracked clean": "is tracked by git and has no uncommitted changes",
		"tracked dirty": "is tracked by git and has uncommitted changes",
		untracked: "is untracked and not ignored, so it exists only on this machine",
	};
	return `${name} ${text[state]}`;
}

function isInside(cwd: string, path: string): boolean {
	const offset = relative(cwd, path);
	return offset === "" || (!offset.startsWith("..") && !isAbsolute(offset));
}

type Outcome = { code: number; stdout: string };

async function git(cwd: string, args: string[]): Promise<Outcome | undefined> {
	try {
		const { stdout } = await run("git", ["-C", cwd, ...args], {
			timeout: GIT_TIMEOUT_MS,
			env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" },
		});
		return { code: 0, stdout };
	} catch (error) {
		const failure = error as { code?: unknown; stdout?: string };
		if (typeof failure.code === "number" && failure.code !== 128) return { code: failure.code, stdout: failure.stdout ?? "" };
		return undefined;
	}
}
