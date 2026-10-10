import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import {
	type AgentEventStream,
	type Conversation,
	type ConversationId,
	type EntryId,
	type Harness,
	type ModelRef,
	type Storage,
	watchEvents,
} from "@earendil-works/pi-durable";
import type { Command, ConversationSummary, Outgoing } from "./protocol.ts";

const context = BACKGROUND_CONTEXT;
const LIST_LIMIT = 500;

export type GatewayOptions = {
	readonly cwd: string;
	readonly harness: Harness;
	readonly model: ModelRef;
	readonly send: (message: Outgoing) => void;
	readonly storage: Storage;
};

export class Gateway {
	private readonly options: GatewayOptions;
	private readonly watchers = new Map<number, AgentEventStream>();

	constructor(options: GatewayOptions) {
		this.options = options;
	}

	async handle(command: Command): Promise<void> {
		try {
			const result = await this.dispatch(command);
			this.options.send({ type: "reply", id: command.id, ok: true, result });
		} catch (error) {
			this.options.send({ type: "reply", id: command.id, ok: false, error: describe(error) });
		}
	}

	async close(): Promise<void> {
		const streams = [...this.watchers.values()];
		this.watchers.clear();
		await Promise.all(streams.map((stream) => stream.stop()));
	}

	private dispatch(command: Command): Promise<unknown> {
		switch (command.type) {
			case "abort":
				return this.abort(command.conversationId);
			case "attach":
				return this.attach(command.conversationId);
			case "create_conversation":
				return this.create(command.cwd);
			case "detach":
				return this.detach(command.conversationId);
			case "fork":
				return this.fork(command.conversationId, command.at);
			case "list_conversations":
				return this.list();
			case "submit":
				return this.submit(command);
		}
	}

	private async abort(conversationId: number) {
		const conversation = await this.conversation(conversationId);
		await conversation.abort(context);
		return {};
	}

	private async attach(conversationId: number) {
		await this.conversation(conversationId);
		await this.stopWatching(conversationId);
		const stream = await watchEvents(this.options.harness, conversationId as ConversationId, context);
		this.watchers.set(conversationId, stream);
		this.options.send({ type: "snapshot", conversationId, snapshot: stream.snapshot });
		await stream.start(async (events) => {
			this.options.send({ type: "events", conversationId, events });
		});
		return {};
	}

	private async create(cwd: string | undefined) {
		const conversation = await this.options.harness.createConversation(
			{
				ownership: { kind: "ownerless" },
				agent: { model: this.options.model, cwd: cwd ?? this.options.cwd },
			},
			context,
		);
		return { conversationId: conversation.id };
	}

	private async detach(conversationId: number) {
		await this.stopWatching(conversationId);
		return {};
	}

	private async fork(conversationId: number, at: number) {
		const conversation = await this.conversation(conversationId);
		const forked = await conversation.fork(at as EntryId, { ownership: { kind: "ownerless" } }, context);
		return { conversationId: forked.id };
	}

	private async list() {
		const page = await this.options.storage.scanConversations({}, LIST_LIMIT, undefined, context);
		const owned = page.items.filter((record) => record.owner === undefined);
		const conversations = await Promise.all(owned.map((record) => this.summarize(record.id)));
		return { conversations };
	}

	private async submit(command: Extract<Command, { type: "submit" }>) {
		const conversation = await this.conversation(command.conversationId);
		const submission = await conversation.submit(
			{
				type: "input",
				content: command.content,
				whenBusy: command.whenBusy,
				requestId: command.requestId,
			},
			context,
		);
		return { submissionId: submission.id };
	}

	private async summarize(id: ConversationId): Promise<ConversationSummary> {
		const conversation = await this.conversation(id);
		const agent = await conversation.agent(context);
		return {
			id,
			cwd: agent.cwd ?? null,
			model: agent.model ? `${agent.model.provider}/${agent.model.modelId}` : null,
		};
	}

	private async conversation(id: number): Promise<Conversation> {
		const conversation = await this.options.harness.conversation(id as ConversationId, context);
		if (conversation === undefined) throw new Error(`unknown conversation ${id}`);
		return conversation;
	}

	private async stopWatching(conversationId: number) {
		const existing = this.watchers.get(conversationId);
		this.watchers.delete(conversationId);
		if (existing) await existing.stop();
	}
}

function describe(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
