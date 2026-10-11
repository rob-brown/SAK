import { createServer, type IncomingMessage, type Server } from "node:http";
import type { AddressInfo } from "node:net";

export type Seen = { method?: string; url?: string; authorization?: string; body: Record<string, any> };
export type Handler = (seen: Seen, count: number) => { status: number; body: unknown };

export async function fakeServer(handler: Handler) {
	const seen: Seen[] = [];
	const server: Server = createServer(async (request: IncomingMessage, response) => {
		const chunks: Buffer[] = [];
		for await (const chunk of request) chunks.push(chunk as Buffer);
		const entry: Seen = {
			method: request.method,
			url: request.url,
			authorization: request.headers.authorization,
			body: JSON.parse(Buffer.concat(chunks).toString() || "{}"),
		};
		seen.push(entry);
		const { status, body } = handler(entry, seen.length);
		response.writeHead(status, { "content-type": "application/json" });
		response.end(typeof body === "string" ? body : JSON.stringify(body));
	});
	await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
	const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
	const close = () => new Promise<void>((resolve) => server.close(() => resolve()));
	return { seen, url, close };
}

export function choiceAnswers(picks: Record<string, [string, number]>) {
	const answers = Object.fromEntries(
		Object.entries(picks).map(([id, [choice, probability]]) => [
			id,
			{ type: "choice", choice, confidence: probability, probabilities: { [choice]: probability } },
		]),
	);
	return { model: "winnow:e4b", answers };
}
