export const MAX_ARGUMENTS = 8;

const NAME_PATTERN = /^[A-Za-z][\w-]{0,31}$/;

export type SkillArgument = {
	readonly name: string;
	readonly description: string | null;
	readonly default: string | null;
	readonly required: boolean;
};

export type ParsedArguments = {
	readonly arguments: readonly SkillArgument[];
	readonly warning: string | null;
};

const NONE: ParsedArguments = { arguments: [], warning: null };

export function parseArguments(fields: Readonly<Record<string, string>>): ParsedArguments {
	const declared = fields.arguments?.trim();
	if (declared) return fromJson(declared);
	const hint = fields["argument-hint"]?.trim();
	return hint ? fromHint(hint) : NONE;
}

function fromJson(text: string): ParsedArguments {
	let parsed: unknown;
	try {
		parsed = JSON.parse(text);
	} catch {
		return failed("arguments must be a JSON list on one line");
	}
	if (!Array.isArray(parsed)) return failed("arguments must be a JSON list");
	const arguments_: SkillArgument[] = [];
	for (const item of parsed) {
		const argument = toArgument(item);
		if (argument === undefined) return failed(`invalid argument ${JSON.stringify(item).slice(0, 60)}`);
		arguments_.push(argument);
	}
	return check(arguments_);
}

function toArgument(item: unknown): SkillArgument | undefined {
	if (typeof item === "string") return named(item, {});
	if (typeof item !== "object" || item === null || Array.isArray(item)) return undefined;
	const { name, description, default: fallback, required } = item as Record<string, unknown>;
	if (typeof name !== "string") return undefined;
	return named(name, { description, fallback, required });
}

function named(
	name: string,
	{ description, fallback, required }: { description?: unknown; fallback?: unknown; required?: unknown },
): SkillArgument | undefined {
	if (!NAME_PATTERN.test(name)) return undefined;
	return {
		name,
		description: typeof description === "string" && description !== "" ? description : null,
		default: typeof fallback === "string" ? fallback : null,
		required: required === true,
	};
}

function fromHint(hint: string): ParsedArguments {
	const arguments_: SkillArgument[] = [];
	for (const match of hint.matchAll(/([[<])\s*([A-Za-z][\w-]*)[^\]>]*[\]>]/g)) {
		const argument = named(match[2] as string, { required: match[1] === "<" });
		if (argument !== undefined) arguments_.push(argument);
	}
	return check(arguments_);
}

function check(arguments_: readonly SkillArgument[]): ParsedArguments {
	if (arguments_.length > MAX_ARGUMENTS) return failed(`at most ${MAX_ARGUMENTS} arguments are supported`);
	const names = arguments_.map((argument) => argument.name.toLowerCase());
	if (new Set(names).size !== names.length) return failed("argument names must be unique");
	return { arguments: arguments_, warning: null };
}

function failed(warning: string): ParsedArguments {
	return { arguments: [], warning };
}
