import { createModels, createProvider, type Model, type MutableModels } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import type { Config } from "./config.ts";

export const PROVIDER_ID = "openai-compatible";

export class ModelCatalog {
	readonly models: MutableModels = createModels();
	private readonly config: Config;
	private readonly ids = new Set<string>();

	constructor(config: Config) {
		this.config = config;
		this.register([config.modelId]);
	}

	async ensure(modelId: string): Promise<void> {
		if (!this.ids.has(modelId)) this.register([modelId]);
	}

	private register(modelIds: readonly string[]) {
		for (const id of modelIds) this.ids.add(id);
		this.models.setProvider(createEndpointProvider(this.config, [...this.ids]));
	}
}

function createEndpointProvider(config: Config, modelIds: readonly string[]) {
	const models = modelIds.map(
		(id): Model<"openai-completions"> => ({
			id,
			name: id,
			api: "openai-completions",
			provider: PROVIDER_ID,
			baseUrl: config.baseUrl,
			reasoning: false,
			input: ["text"],
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			contextWindow: 128000,
			maxTokens: 16000,
		}),
	);

	return createProvider({
		id: PROVIDER_ID,
		name: "OpenAI-compatible",
		baseUrl: config.baseUrl,
		auth: { apiKey: { name: "API key", resolve: async () => ({ auth: { apiKey: config.apiKey } }) } },
		models,
		api: openAICompletionsApi(),
	});
}
