import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { ConversationId, Storage } from "@earendil-works/pi-durable";
import type { RootOf } from "./authorizer.ts";

export function rootConversation(storage: Pick<Storage, "conversation">): RootOf {
	return async (conversationId) => {
		let current = conversationId;
		for (;;) {
			const record = await storage.conversation(current as ConversationId, BACKGROUND_CONTEXT);
			if (record?.owner === undefined) return current;
			current = Number(record.owner.conversationId);
		}
	};
}
