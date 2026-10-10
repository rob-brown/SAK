import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { type Conversation, defineDoc, type Harness } from "@earendil-works/pi-durable";

export const STATES = ["active", "archived", "deleted"] as const;
export type State = (typeof STATES)[number];

export type Meta = { name: string | null; state: State };

const MetaDoc = defineDoc<Meta>({
	kind: "sak.meta",
	version: 1,
	scope: "conversation",
	history: "latest",
	fork: "initial",
	initial: () => ({ name: null, state: "active" }),
});

const DEFAULT_META: Meta = { name: null, state: "active" };

export async function readMeta(harness: Harness, conversationId: number): Promise<Meta> {
	const stored = await harness.snapshot(MetaDoc, conversationId as never, BACKGROUND_CONTEXT);
	return stored ? { name: stored.name, state: stored.state } : DEFAULT_META;
}

export async function writeMeta(conversation: Conversation, patch: Partial<Meta>): Promise<void> {
	await conversation.commit(async (tx) => {
		const doc = await tx.doc(MetaDoc, conversation.id);
		if (patch.name !== undefined) doc.name = patch.name;
		if (patch.state !== undefined) doc.state = patch.state;
	}, BACKGROUND_CONTEXT);
}
