export type JudgeSettings = {
	readonly apiKey?: string;
	readonly baseUrl: string;
	readonly model: string;
	readonly timeoutMs: number;
};

export type JudgeQuestion = {
	readonly type: "choice" | "noul" | "score";
	readonly instructions: unknown;
	readonly criteria?: unknown;
};

export type JudgeResponse = {
	readonly answers: Readonly<Record<string, unknown>>;
};

type Fetch = typeof fetch;

const RETRY_STATUSES = new Set([429, 529]);
const MAX_RETRIES = 2;
const BACKOFF_MS = 250;
const ERROR_CHARS = 500;

export class JudgeClient {
	private readonly fetcher: Fetch;
	private readonly settings: JudgeSettings;

	constructor(settings: JudgeSettings, fetcher: Fetch = fetch) {
		this.fetcher = fetcher;
		this.settings = settings;
	}

	get model(): string {
		return this.settings.model;
	}

	async evaluate(
		state: unknown,
		questions: Readonly<Record<string, JudgeQuestion>>,
		signal?: AbortSignal,
	): Promise<JudgeResponse> {
		const body = JSON.stringify({ model: this.settings.model, state, questions });
		for (let attempt = 0; ; attempt += 1) {
			const response = await this.post(body, signal);
			if (response.ok) return (await response.json()) as JudgeResponse;
			if (RETRY_STATUSES.has(response.status) && attempt < MAX_RETRIES) {
				await pause(BACKOFF_MS * 2 ** attempt, signal);
				continue;
			}
			throw new Error(await failure(response));
		}
	}

	private async post(body: string, signal?: AbortSignal): Promise<Response> {
		const timeout = AbortSignal.timeout(this.settings.timeoutMs);
		const url = `${this.settings.baseUrl.replace(/\/+$/, "")}/v1/systemone`;
		try {
			return await this.fetcher(url, {
				method: "POST",
				headers: {
					"content-type": "application/json",
					...(this.settings.apiKey ? { authorization: `Bearer ${this.settings.apiKey}` } : {}),
				},
				body,
				signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
			});
		} catch (error) {
			if (timeout.aborted) throw new Error(`judge request timed out after ${this.settings.timeoutMs} ms`);
			if (signal?.aborted) throw error;
			throw new Error(`judge server unreachable at ${url}: ${error instanceof Error ? error.message : String(error)}`);
		}
	}
}

async function failure(response: Response): Promise<string> {
	const text = (await response.text().catch(() => "")).trim();
	const detail = text.length > ERROR_CHARS ? `${text.slice(0, ERROR_CHARS)}…` : text;
	return `judge server answered ${response.status}${detail === "" ? "" : `: ${detail}`}`;
}

function pause(ms: number, signal?: AbortSignal): Promise<void> {
	return new Promise((resolve, reject) => {
		const timer = setTimeout(resolve, ms);
		signal?.addEventListener(
			"abort",
			() => {
				clearTimeout(timer);
				reject(signal.reason);
			},
			{ once: true },
		);
	});
}
