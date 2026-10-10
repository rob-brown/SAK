const SNIPPETS: Readonly<Record<string, string>> = {
	read: "Read file contents",
	bash: "Execute bash commands (ls, grep, find, etc.)",
	edit: "Make precise file edits with exact text replacement, including multiple disjoint edits in one call",
	write: "Create or overwrite files",
	codemode: "Run a JavaScript script that calls the other tools; only its output reaches you",
};

export function defaultInstructions(toolNames: readonly string[]): string {
	const listed = toolNames.filter((name) => SNIPPETS[name] !== undefined);
	const tools = listed.map((name) => `- ${name}: ${SNIPPETS[name]}`).join("\n");
	const rules = [
		toolNames.includes("bash") ? "Use bash for file operations like ls, rg, find" : undefined,
		toolNames.includes("codemode")
			? "Use codemode to batch many tool calls or to filter large results; inside a script call tools.read({ path }), tools.bash({ command }) and so on, and return only what you need"
			: undefined,
		"Be concise in your responses",
		"Show file paths clearly when working with files",
	].flatMap((rule) => (rule ? [`- ${rule}`] : []));

	return [
		"You are an expert coding assistant operating inside Sak, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.",
		`Available tools:\n${tools}\n\nIn addition to the tools above, you may have access to other custom tools depending on the project.`,
		`Guidelines:\n${rules.join("\n")}`,
	].join("\n\n");
}
