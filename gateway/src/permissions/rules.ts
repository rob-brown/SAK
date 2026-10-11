import { isAbsolute, relative, resolve } from "node:path";
import { parseCommand } from "./command.ts";

export const MODES = ["accept-edits", "ask", "auto"] as const;

export type Mode = (typeof MODES)[number];
export type Decision = "allow" | "ask" | "deny";

export type Rule = {
	readonly tool: string;
	readonly pattern: string | undefined;
	readonly literal?: boolean;
};

export type Policy = {
	readonly mode: Mode;
	readonly allow: readonly Rule[];
	readonly ask: readonly Rule[];
	readonly deny: readonly Rule[];
};

export type Call = {
	readonly name: string;
	readonly arguments: Readonly<Record<string, unknown>>;
};

type Subject =
	| { readonly kind: "command"; readonly whole: string; readonly segments: readonly string[]; readonly opaque: boolean }
	| { readonly kind: "none" }
	| { readonly kind: "path"; readonly path: string };

const PATH_TOOLS = new Set(["edit", "read", "write"]);

export function parseRule(text: string): Rule {
	const match = /^\s*([A-Za-z][\w-]*)\s*(?:\(([\s\S]*)\))?\s*$/.exec(text);
	if (!match?.[1]) throw new Error(`invalid permission rule "${text}"`);
	const pattern = match[2]?.trim();
	return { tool: match[1].toLowerCase(), pattern: pattern === "" ? undefined : pattern };
}

export function decide(policy: Policy, call: Call, cwd: string): Decision {
	const subject = subjectOf(call, cwd);
	if (anyMatch(policy.deny, call, subject, cwd)) return "deny";
	if (anyMatch(policy.ask, call, subject, cwd)) return "ask";
	if (covered(policy.allow, call, subject, cwd)) return "allow";
	return fallback(policy.mode, call, subject, cwd);
}

export function grantFor(call: Call, cwd: string): Rule[] {
	const subject = subjectOf(call, cwd);
	if (subject.kind === "command") {
		return subject.opaque ? [] : subject.segments.map((segment) => ({ tool: call.name, pattern: segment, literal: true }));
	}
	if (subject.kind === "path") return [{ tool: call.name, pattern: subject.path, literal: true }];
	return [{ tool: call.name, pattern: undefined }];
}

export function summarize(call: Call): string {
	const command = call.arguments.command;
	if (call.name === "bash" && typeof command === "string") return command;
	const path = pathArgument(call);
	if (path !== undefined) return path;
	const text = JSON.stringify(call.arguments);
	return text.length > 200 ? `${text.slice(0, 200)}…` : text;
}

function subjectOf(call: Call, cwd: string): Subject {
	if (call.name === "bash") {
		const whole = typeof call.arguments.command === "string" ? call.arguments.command.trim() : "";
		return { kind: "command", whole, ...parseCommand(whole) };
	}
	const path = PATH_TOOLS.has(call.name) ? pathArgument(call) : undefined;
	return path === undefined ? { kind: "none" } : { kind: "path", path: resolve(cwd, path) };
}

function pathArgument(call: Call): string | undefined {
	const value = call.arguments.path ?? call.arguments.file_path;
	return typeof value === "string" && value !== "" ? value : undefined;
}

function anyMatch(rules: readonly Rule[], call: Call, subject: Subject, cwd: string): boolean {
	return rules.some((rule) => {
		if (rule.tool !== call.name) return false;
		if (rule.pattern === undefined) return true;
		const pattern = rule.pattern;
		if (subject.kind === "command") {
			const direct = [subject.whole, ...subject.segments].some((text) => commandMatches(rule, pattern, text));
			return direct || (subject.opaque && subject.whole.includes(literalPrefix(pattern)));
		}
		return subject.kind === "path" && pathMatches(rule, pattern, subject.path, cwd);
	});
}

function literalPrefix(pattern: string): string {
	return pattern.replace(/(:\*|\s\*|\*.*)$/, "");
}

function covered(rules: readonly Rule[], call: Call, subject: Subject, cwd: string): boolean {
	const own = rules.filter((rule) => rule.tool === call.name);
	if (own.some((rule) => rule.pattern === undefined)) return true;
	if (subject.kind === "command") {
		if (subject.opaque || subject.segments.length === 0) return false;
		return subject.segments.every((segment) => own.some((rule) => commandMatches(rule, rule.pattern as string, segment)));
	}
	if (subject.kind === "path") return own.some((rule) => pathMatches(rule, rule.pattern as string, subject.path, cwd));
	return false;
}

function fallback(mode: Mode, call: Call, subject: Subject, cwd: string): Decision {
	const inside = subject.kind === "path" && isInside(cwd, subject.path);
	if (call.name === "codemode") return "allow";
	if (call.name === "read") return mode === "auto" || inside ? "allow" : "ask";
	if (call.name === "edit" || call.name === "write") {
		return mode === "auto" || (mode === "accept-edits" && inside) ? "allow" : "ask";
	}
	return mode === "auto" ? "allow" : "ask";
}

function commandMatches(rule: Rule, pattern: string, text: string): boolean {
	if (rule.literal) return text === pattern;
	const normalised = pattern.endsWith(":*") ? `${pattern.slice(0, -2)} *` : pattern;
	if (normalised.endsWith(" *")) {
		return new RegExp(`^${wildcards(normalised.slice(0, -2), ".*")}( .*)?$`).test(text);
	}
	return new RegExp(`^${wildcards(normalised, ".*")}$`).test(text);
}

function pathMatches(rule: Rule, pattern: string, path: string, cwd: string): boolean {
	const absolute = resolve(cwd, pattern);
	if (rule.literal) return path === absolute;
	const source = absolute.split("**").map((part) => wildcards(part, "[^/]*")).join(".*");
	return new RegExp(`^${source}$`).test(path);
}

function wildcards(text: string, any: string): string {
	return text
		.split("*")
		.map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
		.join(any);
}

function isInside(cwd: string, path: string): boolean {
	const offset = relative(cwd, path);
	return offset === "" || (!offset.startsWith("..") && !isAbsolute(offset));
}
