import { createModels, createProvider, type Model } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import type { Config } from "./config.ts";

export const PROVIDER_ID = "openai-compatible";

export function createConfiguredModels(config: Config) {
	const model: Model<"openai-completions"> = {
		id: config.modelId,
		name: config.modelId,
		api: "openai-completions",
		provider: PROVIDER_ID,
		baseUrl: config.baseUrl,
		reasoning: false,
		input: ["text"],
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		contextWindow: 128000,
		maxTokens: 16000,
	};

	const provider = createProvider({
		id: PROVIDER_ID,
		name: "OpenAI-compatible",
		baseUrl: config.baseUrl,
		auth: { apiKey: { name: "API key", resolve: async () => ({ auth: { apiKey: config.apiKey } }) } },
		models: [model],
		api: openAICompletionsApi(),
	});

	const models = createModels();
	models.setProvider(provider);
	return models;
}
