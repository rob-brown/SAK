export class Semaphore {
	private available: number;
	private readonly waiting: (() => void)[] = [];

	constructor(permits: number) {
		this.available = permits;
	}

	async run<T>(work: () => Promise<T>): Promise<T> {
		await this.acquire();
		try {
			return await work();
		} finally {
			this.release();
		}
	}

	private acquire(): Promise<void> {
		if (this.available > 0) {
			this.available -= 1;
			return Promise.resolve();
		}
		return new Promise((resolve) => this.waiting.push(resolve));
	}

	private release() {
		const next = this.waiting.shift();
		if (next) next();
		else this.available += 1;
	}
}
