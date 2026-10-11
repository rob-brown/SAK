import { Worker } from "node:worker_threads";

export type WatchOptions = { readonly graceMs?: number; readonly pollMs?: number };

export function watchParent({ graceMs = 10_000, pollMs = 1_000 }: WatchOptions = {}): void {
	const worker = new Worker(new URL("./parent-watchdog-worker.ts", import.meta.url), {
		workerData: { graceMs, parentPid: process.ppid, pollMs },
	});
	worker.unref();
}
