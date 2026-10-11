import type { Context, PermissionBroker } from "./broker.ts";
import { type Call, decide, grantFor, type Policy, type Rule, summarize } from "./rules.ts";

export type Where = {
	readonly conversationId: number;
	readonly cwd: string;
};

export class Authorizer {
	private readonly broker: PermissionBroker;
	private readonly grants = new Map<number, Rule[]>();
	private readonly policy: Policy;

	constructor(policy: Policy, broker: PermissionBroker) {
		this.broker = broker;
		this.policy = policy;
	}

	async authorize(call: Call, where: Where, context: Context): Promise<string | undefined> {
		const granted = this.grants.get(where.conversationId) ?? [];
		const decision = decide({ ...this.policy, allow: [...this.policy.allow, ...granted] }, call, where.cwd);
		const summary = summarize(call);
		if (decision === "allow") return undefined;
		if (decision === "deny") return `Permission denied by a rule: ${call.name} ${summary}`;
		const approval = await this.broker.ask(
			{ conversationId: where.conversationId, tool: call.name, arguments: call.arguments, summary },
			context,
		);
		if (approval === "deny") return `Permission denied by the user: ${call.name} ${summary}`;
		if (approval === "allow_conversation") this.grant(where, call);
		return undefined;
	}

	private grant(where: Where, call: Call) {
		const existing = this.grants.get(where.conversationId) ?? [];
		this.grants.set(where.conversationId, [...existing, ...grantFor(call, where.cwd)]);
	}
}
