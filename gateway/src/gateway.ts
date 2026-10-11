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
import { readMeta, STATES, writeMeta } from "./meta.ts";
import { type Approval, APPROVALS, type PermissionBroker } from "./permissions/broker.ts";
import { DEFAULT_PERSONA_NAME, findPersona, loadPersonas } from "./personas.ts";
import type { Command, ConversationSummary, Outgoing, SubagentSummary } from "./protocol.ts";
import { toolsNamed } from "./tools.ts";

const context = BACKGROUND_CONTEXT;
const LIST_LIMIT = 500;

export type GatewayOptions = {
	readonly broker?: PermissionBroker;
	readonly cwd: string;
	readonly ensureModel: (modelId: string) => Promise<void>;
	readonly harness: Harness;
	readonly listModels: () => Promise<readonly string[]>;
	readonly model: ModelRef;
	readonly personasDir: string;
	readonly send: (message: Outgoing) => void;
	readonly storage: Storage;
};

export class Gateway {
	private defaultModel: ModelRef;
	private readonly options: GatewayOptions;
	private readonly watchers = new Map<number, AgentEventStream>();

	constructor(options: GatewayOptions) {
		this.options = options;
		this.defaultModel = options.model;
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
				return this.create(command);
			case "detach":
				return this.detach(command.conversationId);
			case "fork":
				return this.fork(command.conversationId, command.at);
			case "list_conversations":
				return this.list();
			case "list_personas":
				return this.personas();
			case "list_models":
				return this.models();
			case "list_subagents":
				return this.subagents(command.conversationId);
			case "permission_reply":
				return this.permissionReply(command.requestId, command.approval);
			case "set_meta":
				return this.setMeta(command);
			case "set_model":
				return this.setModel(command.modelId, command.conversationId);
			case "submit":
				return this.submit(command);
		}
	}

	private async subagents(conversationId: number) {
		const { storage, harness } = this.options;
		const owner = conversationId as ConversationId;
		const page = await storage.scanConversations({ ownerConversationId: owner }, LIST_LIMIT, undefined, context);
		const subagents: SubagentSummary[] = await Promise.all(
			page.items.map(async (record) => {
				const meta = await readMeta(harness, record.id);
				const tasks = await storage.scanTasks({ conversationId: record.id }, LIST_LIMIT, undefined, context);
				const live = tasks.items.some((task) => task.state.status !== "terminal");
				return { id: Number(record.id), name: meta.name, persona: meta.persona, live };
			}),
		);
		return { subagents };
	}

	private async permissionReply(requestId: string, approval: Approval) {
		if (!APPROVALS.includes(approval)) throw new Error(`unknown approval ${approval}`);
		return { resolved: this.options.broker?.reply(requestId, approval) ?? false };
	}

	private async models() {
		return { current: this.defaultModel, models: await this.options.listModels() };
	}

	private async setModel(modelId: string, conversationId: number | undefined) {
		await this.options.ensureModel(modelId);
		const model = { provider: this.defaultModel.provider, modelId };
		if (conversationId === undefined) {
			this.defaultModel = model;
			return {};
		}
		const conversation = await this.conversation(conversationId);
		await conversation.configure({ model }, context);
		if (this.watchers.has(conversationId)) await this.attach(conversationId);
		return {};
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
		for (const request of this.options.broker?.pending(conversationId) ?? []) {
			this.options.send({ type: "permission_request", ...request });
		}
		await stream.start(async (events) => {
			this.options.send({ type: "events", conversationId, events });
		});
		return {};
	}

	private async personas() {
		return { personas: await loadPersonas(this.options.personasDir) };
	}

	private async create(command: Extract<Command, { type: "create_conversation" }>) {
		const persona = await findPersona(this.options.personasDir, command.persona ?? DEFAULT_PERSONA_NAME);
		const model = await this.modelFor(command.modelId ?? persona.model ?? undefined);
		const conversation = await this.options.harness.createConversation(
			{
				ownership: { kind: "ownerless" },
				agent: {
					model,
					cwd: command.cwd ?? this.options.cwd,
					instructions: persona.instructions,
					...(persona.tools ? { tools: toolsNamed(persona.tools) } : {}),
				},
			},
			context,
		);
		const name = command.name?.trim();
		await writeMeta(conversation, { persona: persona.name, ...(name ? { name } : {}) });
		return { conversationId: conversation.id };
	}

	private async modelFor(modelId: string | undefined): Promise<ModelRef> {
		if (modelId === undefined) return this.defaultModel;
		await this.options.ensureModel(modelId);
		return { provider: this.defaultModel.provider, modelId };
	}

	private async setMeta(command: Extract<Command, { type: "set_meta" }>) {
		if (command.state !== undefined && !STATES.includes(command.state)) {
			throw new Error(`unknown state ${command.state}`);
		}
		const conversation = await this.conversation(command.conversationId);
		const name = typeof command.name === "string" ? command.name.trim() || null : command.name;
		await writeMeta(conversation, { name, state: command.state });
		return {};
	}

	private async detach(conversationId: number) {
		await this.stopWatching(conversationId);
		return {};
	}

	private async fork(conversationId: number, at: number) {
		const conversation = await this.conversation(conversationId);
		const forked = await conversation.fork(at as EntryId, { ownership: { kind: "ownerless" } }, context);
		const { name } = await readMeta(this.options.harness, conversationId);
		if (name) await writeMeta(forked, { name: `${name} (fork)` });
		return { conversationId: forked.id };
	}

	private async list() {
		const page = await this.options.storage.scanConversations({}, LIST_LIMIT, undefined, context);
		const owned = page.items.filter((record) => record.owner === undefined);
		const summaries = await Promise.all(owned.map((record) => this.summarize(record.id)));
		return { conversations: summaries.filter((summary) => summary.state !== "deleted") };
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
		const meta = await readMeta(this.options.harness, id);
		return {
			id,
			cwd: agent.cwd ?? null,
			model: agent.model ? `${agent.model.provider}/${agent.model.modelId}` : null,
			name: meta.name,
			persona: meta.persona,
			state: meta.state,
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
