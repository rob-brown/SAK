import type { ToolRegistration } from "@earendil-works/pi-durable";
import { CodingTools } from "@earendil-works/pi-durable/tools";
import { Codemode } from "./codemode.ts";
import { AgentCatalogEntry } from "./subagents/catalog.ts";

export const CODEMODE = "codemode";

const CATALOG: readonly ToolRegistration[] = [...(CodingTools.tools ?? []), Codemode, AgentCatalogEntry];

export const TOOL_NAMES: readonly string[] = CATALOG.map((tool) => tool.name);

export function toolsNamed(names: readonly string[]): ToolRegistration[] {
	return CATALOG.filter((tool) => names.includes(tool.name));
}
