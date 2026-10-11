export type ParsedCommand = {
	readonly segments: readonly string[];
	readonly opaque: boolean;
};

export function parseCommand(command: string): ParsedCommand {
	const segments: string[] = [];
	let current = "";
	let quote: '"' | "'" | undefined;
	let opaque = false;

	const flush = () => {
		const trimmed = current.trim();
		if (trimmed !== "") segments.push(trimmed);
		current = "";
	};

	for (let index = 0; index < command.length; index += 1) {
		const char = command[index] as string;
		const next = command[index + 1] ?? "";
		if (quote === "'") {
			current += char;
			if (char === "'") quote = undefined;
			continue;
		}
		if (char === "\\") {
			current += char + next;
			index += 1;
			continue;
		}
		if (char === "`" || (char === "$" && next === "(")) opaque = true;
		if (quote === '"') {
			current += char;
			if (char === '"') quote = undefined;
			continue;
		}
		if (char === "'" || char === '"') {
			quote = char;
			current += char;
			continue;
		}
		if ("<>()".includes(char)) opaque = true;
		if ((char === "&" || char === "|") && next === char) {
			flush();
			index += 1;
			continue;
		}
		if (char === ";" || char === "|" || char === "&" || char === "\n") {
			flush();
			continue;
		}
		current += char;
	}
	if (quote !== undefined) opaque = true;
	flush();
	return { segments, opaque };
}
