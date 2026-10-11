import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { fauxAssistantMessage, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { JudgeClient } from "../src/judge/client.ts";
import { fakeServer } from "./fake-judge.ts";
import { hasEvent, reply, setup, waitFor } from "./support.ts";

const CANNED = { model: "winnow:e4b", answers: { intent: { type: "choice", choice: "invoice", confidence: 0.98 } } };

const QUESTIONS = {
	intent: { type: "choice", instructions: "What does the customer want?", criteria: { invoice: "an invoice", other: "anything else" } },
} as const;

function client(url: string, apiKey?: string, timeoutMs = 5000) {
	return new JudgeClient({ baseUrl: url, model: "winnow:e4b", timeoutMs, ...(apiKey ? { apiKey } : {}) });
}

test("a request goes to /v1/systemone with the model, state and questions, and a key is sent as a bearer token", async () => {
	// Arrange
	const server = await fakeServer(() => ({ status: 200, body: CANNED }));

	// Act
	const keyed = await client(`${server.url}/`, "secret").evaluate("invoice please", QUESTIONS);
	await client(server.url).evaluate("no key", QUESTIONS);

	// Assert
	assert.deepEqual(keyed.answers, CANNED.answers);
	assert.equal(server.seen[0]?.method, "POST");
	assert.equal(server.seen[0]?.url, "/v1/systemone");
	assert.equal(server.seen[0]?.authorization, "Bearer secret");
	assert.deepEqual(server.seen[0]?.body, { model: "winnow:e4b", state: "invoice please", questions: QUESTIONS });
	assert.equal(server.seen[1]?.authorization, undefined);
	await server.close();
});

test("rate limits are retried and other errors report the status and the server's message", async () => {
	// Arrange
	const limited = await fakeServer((_seen, count) => (count < 3 ? { status: 429, body: {} } : { status: 200, body: CANNED }));
	const rejected = await fakeServer(() => ({ status: 401, body: { error: "bad key" } }));

	// Act
	const recovered = await client(limited.url).evaluate("x", QUESTIONS);
	const failure = await client(rejected.url).evaluate("x", QUESTIONS).catch((error: Error) => error);

	// Assert
	assert.equal(limited.seen.length, 3);
	assert.deepEqual(recovered.answers, CANNED.answers);
	assert.match(String(failure), /judge server answered 401: .*bad key/);
	assert.equal(rejected.seen.length, 1);
	await limited.close();
	await rejected.close();
});

test("a server that is down or too slow gives a clear error", async () => {
	// Arrange
	const down = await fakeServer(() => ({ status: 200, body: CANNED }));
	const downUrl = down.url;
	await down.close();
	const slow = await fakeServer(() => ({ status: 200, body: CANNED }));
	const stalled = createServer(() => {});
	await new Promise<void>((resolve) => stalled.listen(0, "127.0.0.1", resolve));
	const stalledUrl = `http://127.0.0.1:${(stalled.address() as AddressInfo).port}`;

	// Act
	const unreachable = await client(downUrl).evaluate("x", QUESTIONS).catch((error: Error) => error);
	const timedOut = await client(stalledUrl, undefined, 100).evaluate("x", QUESTIONS).catch((error: Error) => error);

	// Assert
	assert.match(String(unreachable), /judge server unreachable at .*\/v1\/systemone/);
	assert.match(String(timedOut), /timed out after 100 ms/);
	stalled.closeAllConnections();
	await new Promise<void>((resolve) => stalled.close(() => resolve()));
	await slow.close();
});

async function ask(harness: Awaited<ReturnType<typeof setup>>, args: Record<string, unknown>) {
	harness.faux.setResponses([
		fauxAssistantMessage(fauxToolCall("judge", args as never), { stopReason: "toolUse" }),
		fauxAssistantMessage("noted"),
	]);
	await harness.gateway.handle({ id: "c", type: "create_conversation" });
	const { conversationId } = (reply(harness.outgoing, "c") as { result: { conversationId: number } }).result;
	await harness.gateway.handle({ id: "a", type: "attach", conversationId });
	await harness.gateway.handle({ id: "s", type: "submit", conversationId, content: "go" });
	await waitFor(() => hasEvent(harness.outgoing, "run_end"));
	return JSON.stringify(harness.outgoing.filter((message) => message.type === "events"));
}

test("the judge tool sends the questions and returns the answers, parsing JSON state", async () => {
	// Arrange
	const server = await fakeServer(() => ({ status: 200, body: CANNED }));
	const harness = await setup(undefined, undefined, client(server.url));

	// Act
	const events = await ask(harness, { state: '{"subject":"Invoice?"}', questions: QUESTIONS });

	// Assert
	assert.deepEqual(server.seen[0]?.body.state, { subject: "Invoice?" });
	assert.match(events, /\\"choice\\":\\"invoice\\"/);
	await harness.close();
	await server.close();
});

test("a malformed question is rejected before any request is made, and a server failure is reported to the model", async () => {
	// Arrange
	const failing = await fakeServer(() => ({ status: 422, body: { error: "criteria" } }));
	const harness = await setup(undefined, undefined, client(failing.url));
	const lonely = { intent: { type: "choice", instructions: "pick", criteria: { only: "one" } } };

	// Act
	const invalid = await ask(harness, { state: "x", questions: lonely });
	const other = await setup(undefined, undefined, client(failing.url));
	const rejected = await ask(other, { state: "x", questions: QUESTIONS });

	// Assert
	assert.match(invalid, /a choice needs criteria mapping 2 to 255 options/);
	assert.match(rejected, /judge server answered 422/);
	assert.equal(failing.seen.length, 1);
	await harness.close();
	await other.close();
	await failing.close();
});

const live = await fetch("http://localhost:11435/v1/models", { signal: AbortSignal.timeout(500) }).then(
	(response) => response.ok,
	() => false,
);

test("winnow:e4b on a local ollaya server answers a choice and a yes/no question", { skip: !live }, async () => {
	// Arrange
	const local = new JudgeClient({ baseUrl: "http://localhost:11435", model: "winnow:e4b", timeoutMs: 60_000 });

	// Act
	const { answers } = await local.evaluate("Can I get an invoice for last month?", {
		...QUESTIONS,
		upset: { type: "noul", instructions: "Is the customer angry?" },
	});

	// Assert
	const intent = answers.intent as { choice: string; confidence: number };
	assert.equal(intent.choice, "invoice");
	assert.ok(intent.confidence > 0.5);
	assert.ok((answers.upset as { noul: number }).noul < 0.5);
});
