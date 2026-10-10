export type WhenBusy = "followUp" | "reject" | "steer";

export type Command =
	| { id: string; type: "abort"; conversationId: number }
	| { id: string; type: "attach"; conversationId: number }
	| { id: string; type: "create_conversation"; cwd?: string }
	| { id: string; type: "detach"; conversationId: number }
	| { id: string; type: "fork"; conversationId: number; at: number }
	| { id: string; type: "list_conversations" }
	| { id: string; type: "list_models" }
	| { id: string; type: "submit"; conversationId: number; content: string; whenBusy?: WhenBusy; requestId?: string };

export type ConversationSummary = {
	id: number;
	cwd: string | null;
	model: string | null;
};

export type Outgoing =
	| { type: "reply"; id: string; ok: true; result: unknown }
	| { type: "reply"; id: string | null; ok: false; error: string }
	| { type: "snapshot"; conversationId: number; snapshot: unknown }
	| { type: "events"; conversationId: number; events: unknown };
