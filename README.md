# SAK

A keyboard-driven chat interface for a durable coding agent. Conversations survive restarts, run tools in your project, ask before doing anything risky, and can fan work out to subagents.

SAK is two processes in one repository:

- `gateway/` is a Node program built on the `@earendil-works/pi-*` agent harness. It talks to your model, runs the tools, and stores conversations in SQLite.
- `web/` is a Phoenix LiveView app. It starts the gateway as a child process and gives you the interface at `localhost:4000`.

## Requirements

- Node 22.19 or newer
- Elixir and Erlang (see `web/mix.exs`)
- A model server with an OpenAI-compatible API. The default is `http://localhost:1234/v1` (for example LM Studio).
- Optional: a judge server that speaks TypeSafe's `/v1/systemone` API, such as a local [ollaya](https://ollaya.dev) or TypeSafe's hosted API. See [The judge](#the-judge).

## Quick start

```sh
cd gateway
npm install

cd ../web
mix setup
mix phx.server
```

Open http://localhost:4000. Press `?` for the keyboard help. The gateway starts with the web app.

## Configuration

SAK reads `~/.config/sak/config.toml` once at startup (set `SAK_CONFIG_DIR` to use another directory). Environment variables override the file, and the file overrides the defaults. Restart SAK after editing it. Unknown keys are reported on stderr, and a value of the wrong type stops the gateway with a message naming the file.

```toml
[endpoint]
base_url = "http://localhost:1234/v1"
model = "your-model"

[permissions]
mode = "ask"
allow = ["Bash(git status)", "Bash(git diff *)", "Read(**)"]
deny = ["Bash(rm *)"]

[subagents]
max_concurrent = 6

[judge]
enabled = false
```

| Setting | Environment variable |
| --- | --- |
| model endpoint and model | `SAK_BASE_URL`, `SAK_MODEL` |
| model API key (env only) | `SAK_API_KEY` |
| database path | `SAK_DB` |
| default working directory | `SAK_CWD` |
| config directory | `SAK_CONFIG_DIR` |
| judge endpoint, model, permission model | `SAK_JUDGE_URL`, `SAK_JUDGE_MODEL`, `SAK_JUDGE_PERMISSION_MODEL` |
| judge API key (env only) | `SAK_JUDGE_API_KEY` |

## What you can customise

**Instruction files.** SAK reads `AGENTS.md` or `CLAUDE.md` from your project, from the git root down to the working directory, plus an `AGENTS.md` or `CLAUDE.md` in the SAK config directory that applies to every project and every persona. The chat shows which files were loaded. They are read once, when a conversation starts; start a new session to pick up edits.

**Personas.** Markdown files in `~/.config/sak/personas` with `name`, `description`, `tools`, and optional `model` in the frontmatter; the body is the persona's instructions. A `tools:` line can include patterns, for example `tools: Read, Bash(git diff *)`, which lets that persona run those commands without a prompt. The built-in `default` persona has every tool.

**Skills.** Folders containing a `SKILL.md` under `~/.config/sak/skills` or `.agents/skills` in your project. The model sees each skill's name and description and reads the file when it fits. Skills also appear in the `:` command palette as `skill:<name>`. A skill can declare arguments, which opens a form (`[` and `]` move between fields):

```yaml
arguments: [{"name":"topic","required":true},{"name":"length","default":"short"}]
```

Claude-style `argument-hint: <topic> [length]` also works, where angle brackets mean required.

## Permissions

Every tool call is checked, including calls made from inside a `codemode` script.

- **Rules** look like Claude Code's: `Bash(git diff *)`, `Edit(src/**)`. Precedence is deny, then ask, then allow, then the judge, then the mode.
- **Modes:** `ask` (prompt for bash, write, and edit), `accept-edits` (also run edits inside the working directory), `auto` (run everything no deny rule blocks). Change the mode for one session with the `:permissions` command; subagents follow it unless their persona lacks the tool.
- A prompt offers allow once, allow for the session, or deny. Prompts from subagents appear in the parent conversation and name the subagent.
- Compound shell commands are allowed only if every part is, and command substitution is never auto-allowed.
- These rules limit what the agent calls. They are not a sandbox.

## The judge

The judge is a small decision model that answers typed questions (choice, yes/no, score) with probabilities. It writes no text. SAK uses it in three ways when `[judge] enabled = true`:

- **A `judge` tool** the agent can call, for classifying many items consistently.
- **Internal picks:** choosing a persona for a subagent, and suggesting a matching skill before a message is sent.
- **Permission advice:** put `judge = ["Bash"]` in `[permissions]` and bash commands are scored for how likely they are to destroy unrecoverable data. A score at or above `judge_threshold` (default 0.5 of the top of the scale) becomes a prompt for you. The judge can only add prompts, never remove one, and if it cannot be reached you are asked. Removing only git-ignored files inside the project skips it.

Judge decisions appear in the conversation history but are never sent to the main model.

## Subagents

The agent can delegate with `agent({prompts: [...], persona?})`. Each prompt runs in its own conversation, at most six at a time (`[subagents] max_concurrent`). The Subagents tab on the conversation pane lists the live ones, with a toggle for finished ones; Enter opens a read-only transcript. Subagents do not appear in the session list.

## Using the interface

Press `?` for the full list. A few essentials:

| Key | Action |
| --- | --- |
| `:` | command palette (`model`, `permissions`, `usage`, `clear`, and `skill:<name>`) |
| `/` | search the chat or filter sessions |
| `t` / `o` / `i` | show or hide thinking / tool output / durations and token usage |
| `z` | zoom the focused pane |
| `0` / `1` | focus the chat / the sessions pane |
| `[` / `]` | switch tabs in a pane |

## Development

```sh
cd gateway
npm test
npm run typecheck

cd ../web
mix precommit
node --test assets/js/hooks/*.test.js
```

`CLAUDE.md` describes the architecture and conventions. `roadmap.md` lists what is built, the decisions already made, and how to build the open features: goal mode, telemetry export, Discord, ad-hoc bash, and remote sandboxes.
