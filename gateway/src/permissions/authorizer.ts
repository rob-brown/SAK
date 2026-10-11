import type { JudgeNote } from "../judge/note.ts";
import type { Context, PermissionBroker } from "./broker.ts";
import type { Assessment, PermissionJudge } from "./judge.ts";
import {
	afterJudge,
	type Call,
	decide,
	grantFor,
	type Mode,
	type Policy,
	type Rule,
	type Settled,
	summarize,
} from "./rules.ts";

export type Where = {
	readonly conversationId: number;
	readonly cwd: string;
	readonly record?: (note: JudgeNote) => Promise<void>;
};

export type RootOf = (conversationId: number) => Promise<number>;

export type PersonaRules = (conversationId: number) => Promise<readonly Rule[]>;

const itself: RootOf = async (conversationId) => conversationId;
const noRules: PersonaRules = async () => [];

const NO_JUDGE: Assessment = {
	flagged: true,
	message: "No judge is available, so this needs your decision.",
	note: undefined,
};

export class Authorizer {
	private readonly broker: PermissionBroker;
	private readonly grants = new Map<number, Rule[]>();
	private readonly judge: PermissionJudge | undefined;
	private readonly modes = new Map<number, Mode>();
	private readonly personaRules: PersonaRules;
	private readonly policy: Policy;
	private readonly rootOf: RootOf;

	constructor(
		policy: Policy,
		broker: PermissionBroker,
		rootOf: RootOf = itself,
		judge?: PermissionJudge,
		personaRules: PersonaRules = noRules,
	) {
		this.broker = broker;
		this.judge = judge;
		this.personaRules = personaRules;
		this.policy = policy;
		this.rootOf = rootOf;
	}

	get defaultMode(): Mode {
		return this.policy.mode;
	}

	modeFor(conversationId: number): Mode {
		return this.modes.get(conversationId) ?? this.policy.mode;
	}

	setMode(conversationId: number, mode: Mode) {
		this.modes.set(conversationId, mode);
	}

	async authorize(call: Call, where: Where, context: Context): Promise<string | undefined> {
		const root = await this.rootOf(where.conversationId);
		const mode = this.modeFor(root);
		const granted = this.grants.get(root) ?? [];
		const fromPersona = await this.personaRules(where.conversationId);
		const effective = { ...this.policy, mode, allow: [...this.policy.allow, ...fromPersona, ...granted] };
		const summary = summarize(call);
		let note: string | undefined;
		let decision: Settled | "judge" = decide(effective, call, where.cwd);
		if (decision === "judge") {
			const verdict = await this.verdict(call, where, context);
			decision = verdict.flagged ? "ask" : afterJudge(mode, call, where.cwd);
			note = verdict.flagged ? verdict.message : undefined;
		}
		if (decision === "allow") return undefined;
		if (decision === "deny") return `Permission denied by a rule: ${call.name} ${summary}`;
		const approval = await this.broker.ask(
			{
				conversationId: root,
				tool: call.name,
				arguments: call.arguments,
				summary,
				...(note === undefined ? {} : { note }),
				...(root === where.conversationId ? {} : { subagent: where.conversationId }),
			},
			context,
		);
		if (approval === "deny") return `Permission denied by the user: ${call.name} ${summary}`;
		if (approval === "allow_conversation") this.grant(root, call, where.cwd);
		return undefined;
	}

	private async verdict(call: Call, where: Where, context: Context): Promise<Assessment> {
		if (this.judge === undefined) return NO_JUDGE;
		const assessment = await this.judge.assess(call, where.cwd, context.abortSignal);
		if (assessment.note !== undefined) await where.record?.(assessment.note);
		return assessment;
	}

	private grant(root: number, call: Call, cwd: string) {
		const existing = this.grants.get(root) ?? [];
		this.grants.set(root, [...existing, ...grantFor(call, cwd)]);
	}
}
