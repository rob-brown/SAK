import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { acquireInstanceLock } from "../src/instance-lock.ts";

const FIXTURE = new URL("./orphan-fixture.ts", import.meta.url).pathname;

async function databasePath(): Promise<string> {
	return join(await mkdtemp(join(tmpdir(), "sak-lock-")), "sak.sqlite");
}

function alive(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

test("a second gateway cannot take the lock on the same database until the first releases it", async () => {
	// Arrange
	const dbPath = await databasePath();
	const first = await acquireInstanceLock(dbPath, 0);

	// Act
	const second = acquireInstanceLock(dbPath, 0);

	// Assert
	await assert.rejects(second, /another gateway is already using/);
	first.release();
	const third = await acquireInstanceLock(dbPath, 0);
	third.release();
});

test("a gateway waits for the lock and takes it when the previous holder lets go", async () => {
	// Arrange
	const dbPath = await databasePath();
	const first = await acquireInstanceLock(dbPath, 0);
	setTimeout(() => first.release(), 400);

	// Act
	const second = await acquireInstanceLock(dbPath, 5_000);

	// Assert
	second.release();
});

test("a gateway stays up while its parent lives and exits once the parent dies, even with its main thread stuck in a loop", async () => {
	// Arrange
	const launcher = spawn("sh", ["-c", `node ${FIXTURE} & pid=$!; sleep 1; echo $pid`], {
		stdio: ["ignore", "pipe", "ignore"],
	});
	const pid = await new Promise<number>((resolve) => {
		launcher.stdout.once("data", (chunk: Buffer) => resolve(Number(chunk.toString().trim())));
	});
	launcher.stdout.destroy();
	const aliveWhileParentLived = alive(pid);

	// Act
	const deadline = Date.now() + 8_000;
	while (alive(pid) && Date.now() < deadline) await sleep(100);

	// Assert
	const survived = alive(pid);
	if (survived) process.kill(pid, "SIGKILL");
	assert.equal(aliveWhileParentLived, true);
	assert.equal(survived, false);
});
