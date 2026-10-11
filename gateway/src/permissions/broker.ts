import { randomUUID } from "node:crypto";
import { awaitWithContext } from "@earendil-works/chord/context";
import type { Outgoing } from "../protocol.ts";

export type Context = Parameters<typeof awaitWithContext>[1];

export const APPROVALS = ["allow", "allow_conversation", "deny"] as const;

export type Approval = (typeof APPROVALS)[number];

export type PermissionRequest = {
	readonly requestId: string;
	readonly conversationId: number;
	readonly tool: string;
	readonly arguments: Readonly<Record<string, unknown>>;
	readonly summary: string;
	readonly subagent?: number;
};

type Waiting = {
	readonly request: PermissionRequest;
	readonly resolve: (approval: Approval) => void;
};

export class PermissionBroker {
	private readonly send: (message: Outgoing) => void;
	private readonly waiting = new Map<string, Waiting>();

	constructor(send: (message: Outgoing) => void) {
		this.send = send;
	}

	async ask(request: Omit<PermissionRequest, "requestId">, context: Context): Promise<Approval> {
		const full: PermissionRequest = { requestId: randomUUID(), ...request };
		const answer = new Promise<Approval>((resolve) => {
			this.waiting.set(full.requestId, { request: full, resolve });
		});
		this.send({ type: "permission_request", ...full });
		try {
			return await awaitWithContext(answer, context);
		} finally {
			if (this.waiting.delete(full.requestId)) this.announceResolved(full);
		}
	}

	reply(requestId: string, approval: Approval): boolean {
		const entry = this.waiting.get(requestId);
		if (entry === undefined) return false;
		this.waiting.delete(requestId);
		this.announceResolved(entry.request);
		entry.resolve(approval);
		return true;
	}

	pending(conversationId: number): PermissionRequest[] {
		return [...this.waiting.values()]
			.map((entry) => entry.request)
			.filter((request) => request.conversationId === conversationId);
	}

	private announceResolved(request: PermissionRequest) {
		this.send({ type: "permission_resolved", conversationId: request.conversationId, requestId: request.requestId });
	}
}
