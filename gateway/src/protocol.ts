import type { State } from "./meta.ts";

export type WhenBusy = "followUp" | "reject" | "steer";

export type Command =
	| { id: string; type: "abort"; conversationId: number }
	| { id: string; type: "attach"; conversationId: number }
	| { id: string; type: "create_conversation"; cwd?: string; modelId?: string; name?: string; persona?: string }
	| { id: string; type: "list_personas" }
	| { id: string; type: "set_meta"; conversationId: number; name?: string | null; state?: State }
	| { id: string; type: "detach"; conversationId: number }
	| { id: string; type: "fork"; conversationId: number; at: number }
	| { id: string; type: "list_conversations" }
	| { id: string; type: "list_models" }
	| { id: string; type: "list_skills"; conversationId: number }
	| { id: string; type: "list_subagents"; conversationId: number }
	| { id: string; type: "permission_mode"; conversationId: number; mode?: "accept-edits" | "ask" | "auto" }
	| { id: string; type: "permission_reply"; requestId: string; approval: "allow" | "allow_conversation" | "deny" }
	| { id: string; type: "set_model"; modelId: string; conversationId?: number }
	| { id: string; type: "submit"; conversationId: number; content: string; whenBusy?: WhenBusy; requestId?: string };

export type ConversationSummary = {
	id: number;
	cwd: string | null;
	model: string | null;
	name: string | null;
	persona: string | null;
	state: State;
};

export type SubagentSummary = {
	id: number;
	name: string | null;
	persona: string | null;
	live: boolean;
};

export type Outgoing =
	| { type: "reply"; id: string; ok: true; result: unknown }
	| { type: "reply"; id: string | null; ok: false; error: string }
	| { type: "snapshot"; conversationId: number; snapshot: unknown }
	| { type: "events"; conversationId: number; events: unknown }
	| {
			type: "permission_request";
			requestId: string;
			conversationId: number;
			tool: string;
			arguments: Readonly<Record<string, unknown>>;
			summary: string;
			subagent?: number;
			note?: string;
	  }
	| { type: "permission_resolved"; conversationId: number; requestId: string };
