# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SAK is a keyboard-driven chat UI for a durable coding agent. It is two processes in one repo:

- `gateway/` — Node (>=22.19, runs `.ts` directly, no build step) wrapper around the `@earendil-works/pi-*` / `chord` agent harness. Persists conversations in SQLite.
- `web/` — Phoenix 1.8 / LiveView app. It spawns the gateway as a child process and renders its conversations.

`README.md` is the user-facing overview. `roadmap.md` lists what exists, the settled decisions, and how to build the open features (goal mode, telemetry export, Discord, ad-hoc bash, remote sandboxes). Read it before proposing or starting a feature.

## Commands

Gateway (run from `gateway/`):

- `npm start` — run the gateway standalone (reads JSON lines on stdin)
- `npm test` — `node --test test/*.test.ts`; single file: `node --test test/personas.test.ts`
- `npm run typecheck` — `tsc -p tsconfig.json`

Web (run from `web/`):

- `mix setup` — deps + asset tooling + asset build
- `mix phx.server` — dev server on `localhost:4000` (also spawns the gateway)
- `mix test` — excludes `:integration` tests; single file: `mix test test/sak/chat_test.exs`, single test: `mix test path:LINE`
- `mix test --only integration` — runs the real gateway end to end (`test/sak/gateway_integration_test.exs`)
- `mix precommit` — compile with warnings-as-errors, unlock unused deps, format, test. Run before finishing changes (`web/AGENTS.md` requires it).
- JS hook tests: `node --test assets/js/hooks/*.test.js` (plain `node:test`, no bundler)

`web/AGENTS.md` holds the Phoenix/LiveView/HEEx conventions for this repo (streams, `to_form`, `<.input>`, `<.icon>`, no inline scripts, colocated hooks, `Layouts.app` wrapper, etc.). Read it before editing templates or LiveViews.

Testing notes:

- Gateway tests that start a fake HTTP server (`test/fake-judge.ts`) leave it open when they fail, so a failing run **hangs instead of exiting**. Treat a hang as a failure and run the single file.
- Live tests against a local ollaya server skip themselves when it is unreachable.
- After changing JS or CSS, production needs `mix assets.deploy` or the browser keeps the old bundle. `web/scripts/prod` is the user's own launch script; do not include edits to it in commits.
- Mutation-check new tests: break the guard, see the test fail, restore it.

## Architecture

### Gateway protocol (the seam between the two halves)

`Sak.Gateway` (`web/lib/sak/gateway.ex`) is a GenServer that owns the Node process via a `Port` and speaks newline-delimited JSON over stdio. Command and message shapes live in `gateway/src/protocol.ts`; the Elixir side is untyped maps, so **change both sides together**.

- Requests: `Sak.Gateway.request(type, params)` sends `{id, type, ...params}`; the reply is matched by `id` (`{:ok, result}` / `{:error, msg}`). Commands are processed serially on the gateway side (`main.ts` queue).
- Pushes: `snapshot`, `events`, and `permission_request` / resolved messages are broadcast on PubSub topic `Sak.Gateway.conversation_topic(id)`; a conversation only streams after an `attach` command. After the gateway (re)starts it broadcasts `:gateway_started` on `started_topic/0` so LiveViews re-attach.
- `Gateway` class (`gateway/src/gateway.ts`) dispatches commands onto the pi-durable `Harness`: create/fork/submit/abort/attach/detach, model switching, personas, per-conversation metadata, `permission_reply`, `permission_mode`, `list_subagents`, `list_skills`.
- Per-conversation metadata (name, persona, `active|archived|deleted` state) is a durable doc defined in `gateway/src/meta.ts`; deletion is a soft state, filtered out of `list_conversations`. Conversations owned by a task (subagent children) are also filtered out.
- Tests swap the gateway for a fake: `test/support/fake_gateway_client.ex` (and `fake_gateway.exs` for a fake process) via the `:fake_gateway_replies` app env. `config/test.exs` sets `gateway: nil` so tests don't spawn it.

### Gateway internals

- **Config** (`gateway/src/config.ts`): `$SAK_CONFIG_DIR/config.toml` (default `~/.config/sak/config.toml`) parsed with `smol-toml`. Precedence env > file > default. Sections: `endpoint`, `storage`, `instructions`, `permissions`, `subagents`, `judge`. Environment: `SAK_BASE_URL`, `SAK_MODEL`, `SAK_DB`, `SAK_CWD`, `SAK_CONFIG_DIR`, `SAK_API_KEY`, `SAK_JUDGE_URL`, `SAK_JUDGE_MODEL`, `SAK_JUDGE_PERMISSION_MODEL`, `SAK_JUDGE_API_KEY`. API keys are env-only, never read from the file. Unknown keys warn on stderr; a wrong type stops the gateway with exit 2. New settings go in the `SCHEMA` there with a kind (`count`, `flag`, `list`, `mode`, `ratio`, `text`).
- **Prompt sections** (`open.ts`): `cwd`, `project_instructions` (`AGENTS.md` or `CLAUDE.md` from the SAK config directory, then from the git root down to cwd), and `skills` (folders with `SKILL.md` under `$SAK_CONFIG_DIR/skills` and `.agents/skills`). **These sections are frozen at a conversation's first turn** via `frozenSection`: the models do not accept mid-conversation system messages, so changing one would rewrite the leading system message and invalidate the prompt cache for the whole conversation. Append content as ordinary messages; never rewrite earlier content. Edits to instruction files apply to new sessions only, by design.
- **Personas** (`personas.ts`): markdown files in `$SAK_CONFIG_DIR/personas`, plus a builtin `default`. Claude-style tool names are aliased; entries with a pattern such as `Bash(git diff *)` become allow rules for that persona (`permissions/persona-rules.ts`). The `codemode` tool (`codemode.ts`) runs a sandboxed script that calls the other tools.
- **Permissions** (`permissions/`): Claude-style `Tool(pattern)` rules (`rules.ts`), order deny, ask, allow, judge, then the mode (`ask` / `accept-edits` / `auto`). A `wrapTool` guard (`extension.ts`) gates every tool call, including calls from inside `codemode`. Prompts wait in `broker.ts` and are re-sent on attach. The mode and "allow for this session" grants are per root conversation, held in gateway memory. Subagent prompts route to the root conversation. Bash commands are split on `&& || ; | & newline`; command substitution makes a command opaque and never auto-allowed.
- **Judge** (`judge/`): a client for TypeSafe's `/v1/systemone` (also served by a local ollaya server), the `judge` tool, and internal uses (persona pick, skill suggestion, permission assessment). The judge is advice: the permission judge (`permissions/judge.ts`) can only turn a call into a human prompt, never remove one, and it fails safe to asking. It scores a four-level question and compares `score / 3` with `judge_threshold` (default 0.5). Internal picks threshold on the chosen option's probability, not TypeSafe's `confidence`. Decisions are recorded as `sak.judge` entries (no `model` field, so they show in history but never reach the model).
- **Subagents** (`subagents/`): `agent({prompts, persona?})`, a gateway-wide `Semaphore` (default 6), children are task-owned conversations that cannot spawn subagents, replay-safe through per-call memo keys and request ids. A `persona` that matches no name is treated as a description and the judge picks the closest.

### Web side

- `Sak.Chat` (`web/lib/sak/chat.ex`) is a pure model that folds the gateway's snapshot and event batches into display items and returns LiveView stream ops (`{:insert, item}`, `{:delete, item}`, `:reset`). Keep it free of socket concerns.
- `Sak.ChatFields` decides the visible and searchable text of each item, so rendering and search agree. `Sak.JudgeFormat` and `Sak.AgentFormat` turn judge and agent tool calls and results into readable markdown (agent output is cut to 3 items of 2000 characters). `Sak.Fence` builds code fences that survive backticks.
- `SakWeb.ChatLive` is the single LiveView. Its behavior is split into modules under `web/lib/sak_web/live/chat_live/` (`Keys`, `Sessions`, `Entries`, `Items`, `NewSession`, `Models`, `Search`, `Mention`, `Command`, `Confirm`, `Manage`, `Events`, `Render`, `Permission`, `PermissionMode`, `Subagents`, `UsagePanel`, `SkillForm`), each taking and returning the socket. `ChatLive` itself mostly routes `handle_info`/`handle_event` to them.
- Keyboard handling is layered: the JS `key_router` hook decides which keys go to the server (it reads `data-*-open` flags on `#sak`, and leaves any key pressed with cmd to the browser), and `ChatLive.Keys` routes by the active modal (precedence: permission, mode picker, usage, skill form, help, models, wizard, confirm, rename, command, chat search, sessions filter) or falls back to global keys. A new modal needs both a `data-*` flag and a `modal/1` clause. When a permission request arrives, `Permission.received` closes the other overlays. Keybindings and help text come from `Sak.Keybindings` / `Sak.Help` / `Sak.Hints`.
- `Sak.*` modules hold the pure logic (fuzzy match, file index/picker, command parsing, new-session wizard state, session/entry row building, usage totals, skill prompts, markdown via `mdex`); `SakWeb.*Components` / `Dialogs` / `Overlays` / `WizardOverlay` are the presentation layer.

## Repo notes

- `web/priv/static/assets/` is gitignored build output; digested files elsewhere in `web/priv/static/` show up as untracked after `mix assets.deploy`.
- `*.sqlite*` files (the conversation DB, created in the gateway's working directory) are gitignored.
- New npm or hex dependencies need the user's approval; each one so far has been approved by name.
