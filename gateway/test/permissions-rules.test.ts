import assert from "node:assert/strict";
import { test } from "node:test";
import { parseCommand } from "../src/permissions/command.ts";
import { afterJudge, type Call, decide, grantFor, type Mode, parseRule, type Policy } from "../src/permissions/rules.ts";

const CWD = "/work/app";

function policy(mode: Mode, rules: { allow?: string[]; ask?: string[]; deny?: string[] } = {}): Policy {
	return {
		mode,
		allow: (rules.allow ?? []).map(parseRule),
		ask: (rules.ask ?? []).map(parseRule),
		deny: (rules.deny ?? []).map(parseRule),
	};
}

function bash(command: string): Call {
	return { name: "bash", arguments: { command } };
}

function file(name: string, path: string): Call {
	return { name, arguments: { path } };
}

test("a rule is a lowercase tool name with an optional pattern, and nonsense is rejected", () => {
	// Arrange
	const valid = ["Bash(ls *)", "Read", "Edit(src/**)"];

	// Act
	const parsed = valid.map(parseRule);

	// Assert
	assert.deepEqual(parsed, [
		{ tool: "bash", pattern: "ls *" },
		{ tool: "read", pattern: undefined },
		{ tool: "edit", pattern: "src/**" },
	]);
	assert.throws(() => parseRule("(oops)"), /invalid permission rule/);
});

test("a command is split on shell operators outside quotes and substitution makes it opaque", () => {
	// Arrange
	const commands = ["ls -la && echo 'a; b' | grep x", "ls $(whoami)", "echo hi > out.txt", 'echo "unterminated'];

	// Act
	const [chained, substitution, redirect, unterminated] = commands.map(parseCommand);

	// Assert
	assert.deepEqual(chained, { segments: ["ls -la", "echo 'a; b'", "grep x"], opaque: false });
	assert.equal(substitution?.opaque, true);
	assert.equal(redirect?.opaque, true);
	assert.equal(unterminated?.opaque, true);
});

test("an allow pattern covers the command and its arguments but not look-alikes", () => {
	// Arrange
	const rules = policy("ask", { allow: ["Bash(ls *)", "Bash(git diff:*)"] });

	// Act
	const decisions = ["ls", "ls -la", "lsof", "git diff", "git diff HEAD~1", "git difftool"].map((command) =>
		decide(rules, bash(command), CWD),
	);

	// Assert
	assert.deepEqual(decisions, ["allow", "allow", "ask", "allow", "allow", "ask"]);
});

test("every part of a compound command must be allowed, and substitution is never auto-allowed", () => {
	// Arrange
	const rules = policy("ask", { allow: ["Bash(ls *)", "Bash(grep *)"] });

	// Act
	const piped = decide(rules, bash("ls | grep x"), CWD);
	const smuggled = decide(rules, bash("ls; rm -rf /"), CWD);
	const substituted = decide(rules, bash("ls $(rm x)"), CWD);

	// Assert
	assert.equal(piped, "allow");
	assert.equal(smuggled, "ask");
	assert.equal(substituted, "ask");
});

test("deny beats ask beats allow, and deny also catches a command hidden in substitution", () => {
	// Arrange
	const rules = policy("auto", { allow: ["Bash"], ask: ["Bash(git push *)"], deny: ["Bash(rm *)"] });

	// Act
	const denied = decide(rules, bash("echo ok && rm -rf build"), CWD);
	const hidden = decide(rules, bash("echo $(rm -rf build)"), CWD);
	const asked = decide(rules, bash("git push origin main"), CWD);
	const allowed = decide(rules, bash("echo fine"), CWD);

	// Assert
	assert.deepEqual([denied, hidden, asked, allowed], ["deny", "deny", "ask", "allow"]);
});

test("path rules are resolved against the working directory", () => {
	// Arrange
	const rules = policy("ask", { allow: ["Edit(src/**)", "Read(*.md)"] });

	// Act
	const nested = decide(rules, file("edit", "src/a/b.ts"), CWD);
	const outside = decide(rules, file("edit", "lib/b.ts"), CWD);
	const markdown = decide(rules, file("read", "README.md"), CWD);
	const deepMarkdown = decide(rules, file("read", "/etc/notes.md"), CWD);

	// Assert
	assert.deepEqual([nested, outside, markdown, deepMarkdown], ["allow", "ask", "allow", "ask"]);
});

test("modes decide what needs approval when no rule matches", () => {
	// Arrange
	const calls = [bash("make"), file("read", "a.txt"), file("read", "/etc/passwd"), file("edit", "a.txt"), file("write", "/tmp/x"), { name: "codemode", arguments: {} }];

	// Act
	const table = (["ask", "accept-edits", "auto"] as const).map((mode) => calls.map((call) => decide(policy(mode), call, CWD)));

	// Assert
	assert.deepEqual(table, [
		["ask", "allow", "ask", "ask", "ask", "allow"],
		["ask", "allow", "ask", "allow", "ask", "allow"],
		["allow", "allow", "allow", "allow", "allow", "allow"],
	]);
});

test("a grant for a command is literal per segment and nothing is granted for opaque commands", () => {
	// Arrange
	const compound = bash("ls *.ts && echo done");
	const opaque = bash("echo $(date)");

	// Act
	const rules = grantFor(compound, CWD);
	const granted = policy("ask", { allow: [] });
	const withGrant = { ...granted, allow: rules };

	// Assert
	assert.equal(decide(withGrant, compound, CWD), "allow");
	assert.equal(decide(withGrant, bash("ls *.ts /etc"), CWD), "ask");
	assert.deepEqual(grantFor(opaque, CWD), []);
});

test("judge rules come after deny, ask and allow, and before the mode", () => {
	// Arrange
	const rules = (extra: Partial<Record<"allow" | "ask" | "deny", string[]>>): Policy => ({
		mode: "auto",
		allow: (extra.allow ?? []).map(parseRule),
		ask: (extra.ask ?? []).map(parseRule),
		deny: (extra.deny ?? []).map(parseRule),
		judge: ["Bash"].map(parseRule),
	});

	// Act
	const plain = decide(rules({}), bash("make"), CWD);
	const allowed = decide(rules({ allow: ["Bash(make)"] }), bash("make"), CWD);
	const asked = decide(rules({ ask: ["Bash(make)"] }), bash("make"), CWD);
	const denied = decide(rules({ deny: ["Bash(make)"] }), bash("make"), CWD);
	const unmatched = decide(rules({}), file("read", "a.txt"), CWD);

	// Assert
	assert.deepEqual([plain, allowed, asked, denied, unmatched], ["judge", "allow", "ask", "deny", "allow"]);
});

test("after a clean verdict the mode decides, so the judge can never remove a prompt", () => {
	// Arrange
	const call = bash("make");

	// Act
	const results = (["ask", "accept-edits", "auto"] as const).map((mode) => afterJudge(mode, call, CWD));

	// Assert
	assert.deepEqual(results, ["ask", "ask", "allow"]);
});
