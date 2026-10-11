import type { Harness } from "@earendil-works/pi-durable";
import { readMeta } from "../meta.ts";
import { findPersona } from "../personas.ts";
import type { PersonaRules } from "./authorizer.ts";

export type HarnessRef = { harness?: Harness };

export function personaRulesFor(personasDir: string, ref: HarnessRef): PersonaRules {
	return async (conversationId) => {
		if (ref.harness === undefined) return [];
		const { persona } = await readMeta(ref.harness, conversationId);
		if (persona === null) return [];
		return (await findPersona(personasDir, persona).catch(() => undefined))?.rules ?? [];
	};
}
