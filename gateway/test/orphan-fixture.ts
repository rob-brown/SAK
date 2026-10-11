import { watchParent } from "../src/parent-watchdog.ts";

watchParent({ graceMs: 300, pollMs: 100 });
setTimeout(() => {
	for (;;);
}, 1_500);
