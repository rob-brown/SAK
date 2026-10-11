import type { Context, PermissionBroker } from "./broker.ts";
import { type Call, decide, grantFor, type Policy, type Rule, summarize } from "./rules.ts";

export type Where = {
	readonly conversationId: number;
	readonly cwd: string;
};

export type RootOf = (conversationId: number) => Promise<number>;

const itself: RootOf = async (conversationId) => conversationId;

export class Authorizer {
	private readonly broker: PermissionBroker;
	private readonly grants = new Map<number, Rule[]>();
	private readonly policy: Policy;
	private readonly rootOf: RootOf;

	constructor(policy: Policy, broker: PermissionBroker, rootOf: RootOf = itself) {
		this.broker = broker;
		this.policy = policy;
		this.rootOf = rootOf;
	}

	async authorize(call: Call, where: Where, context: Context): Promise<string | undefined> {
		const root = await this.rootOf(where.conversationId);
		const granted = this.grants.get(root) ?? [];
		const decision = decide({ ...this.policy, allow: [...this.policy.allow, ...granted] }, call, where.cwd);
		const summary = summarize(call);
		if (decision === "allow") return undefined;
		if (decision === "deny") return `Permission denied by a rule: ${call.name} ${summary}`;
		const approval = await this.broker.ask(
			{
				conversationId: root,
				tool: call.name,
				arguments: call.arguments,
				summary,
				...(root === where.conversationId ? {} : { subagent: where.conversationId }),
			},
			context,
		);
		if (approval === "deny") return `Permission denied by the user: ${call.name} ${summary}`;
		if (approval === "allow_conversation") this.grant(root, call, where.cwd);
		return undefined;
	}

	private grant(root: number, call: Call, cwd: string) {
		const existing = this.grants.get(root) ?? [];
		this.grants.set(root, [...existing, ...grantFor(call, cwd)]);
	}
}
