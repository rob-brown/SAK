import { workerData } from "node:worker_threads";

const { graceMs, parentPid, pollMs } = workerData as { graceMs: number; parentPid: number; pollMs: number };

const poll = setInterval(() => {
	if (process.ppid === parentPid) return;
	clearInterval(poll);
	setTimeout(() => process.kill(process.pid, "SIGKILL"), graceMs);
}, pollMs);
