export function splitFrontmatter(text: string): { fields: Record<string, string>; body: string } {
	const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/.exec(text);
	if (!match) return { fields: {}, body: text };
	const fields: Record<string, string> = {};
	for (const line of (match[1] ?? "").split(/\r?\n/)) {
		const field = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(line);
		if (field?.[1] !== undefined) fields[field[1]] = field[2] ?? "";
	}
	return { fields, body: match[2] ?? "" };
}
