import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

export function git(cwd: string, ...args: string[]) {
	execFileSync("git", ["-C", cwd, "-c", "user.email=t@t", "-c", "user.name=t", ...args], { stdio: "ignore" });
}

export async function repo() {
	const directory = await mkdtemp(join(tmpdir(), "sak-facts-"));
	git(directory, "init", "-q");
	await mkdir(join(directory, "src"));
	await mkdir(join(directory, "build"));
	await writeFile(join(directory, ".gitignore"), "build/\n");
	await writeFile(join(directory, "src", "a.ts"), "export const a = 1;\n");
	await writeFile(join(directory, "build", "out.js"), "built\n");
	git(directory, "add", ".gitignore", "src");
	git(directory, "commit", "-q", "-m", "init");
	await writeFile(join(directory, "notes.txt"), "mine\n");
	return directory;
}
