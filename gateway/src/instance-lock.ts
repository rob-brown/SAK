import { DatabaseSync } from "node:sqlite";
import { setTimeout as sleep } from "node:timers/promises";

const SQLITE_BUSY = 5;
const RETRY_MS = 250;

export type InstanceLock = { release(): void };

export async function acquireInstanceLock(dbPath: string, waitMs: number): Promise<InstanceLock> {
	const deadline = Date.now() + waitMs;
	for (;;) {
		const lock = tryLock(`${dbPath}-lock`);
		if (lock !== undefined) return lock;
		if (Date.now() >= deadline) throw new Error(`another gateway is already using ${dbPath}`);
		await sleep(RETRY_MS);
	}
}

function tryLock(lockPath: string): InstanceLock | undefined {
	const db = new DatabaseSync(lockPath);
	try {
		db.exec("BEGIN EXCLUSIVE");
	} catch (error) {
		db.close();
		if ((error as { errcode?: number }).errcode === SQLITE_BUSY) return undefined;
		throw error;
	}	return { release: () => db.close() };
}
