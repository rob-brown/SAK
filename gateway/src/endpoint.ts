export async function listEndpointModels(baseUrl: string, apiKey: string): Promise<readonly string[]> {
	const response = await fetch(`${baseUrl.replace(/\/+$/, "")}/models`, {
		headers: { authorization: `Bearer ${apiKey}` },
	});
	if (!response.ok) throw new Error(`model list failed: HTTP ${response.status}`);
	const body = (await response.json()) as { data?: readonly { id?: unknown }[] };
	return (body.data ?? []).flatMap((entry) => (typeof entry.id === "string" ? [entry.id] : []));
}
