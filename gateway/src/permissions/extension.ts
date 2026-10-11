import { defineExtension, type ToolRegistration, wrapTool } from "@earendil-works/pi-durable";
import { CodingTools } from "@earendil-works/pi-durable/tools";
import type { Authorizer } from "./authorizer.ts";

export function permissionsExtension(authorizer: Authorizer) {
	const wraps = (CodingTools.tools ?? []).map((tool) => wrapTool(tool, (target) => guarded(target, authorizer)));
	return defineExtension({ name: "permissions", wraps });
}

function guarded<T extends ToolRegistration>(tool: T, authorizer: Authorizer): T {
	const execute: ToolRegistration["execute"] = async (args, api, context) => {
		const denial = await authorizer.authorize(
			{ name: tool.name, arguments: args as Record<string, unknown> },
			{ conversationId: api.conversationId, cwd: api.env?.cwd ?? process.cwd() },
			context,
		);
		if (denial !== undefined) return { content: [{ type: "text", text: denial }], isError: true };
		return tool.execute(args, api, context);
	};
	return { ...tool, execute };
}
