# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Sak is a keyboard-driven chat UI for a durable coding agent. It is two processes in one repo:

- `gateway/` — Node (>=22.19, runs `.ts` directly, no build step) wrapper around the `@earendil-works/pi-*` / `chord` agent harness. Persists conversations in SQLite.
- `web/` — Phoenix 1.8 / LiveView app. It spawns the gateway as a child process and renders its conversations.

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

## Architecture

### Gateway protocol (the seam between the two halves)

`Sak.Gateway` (`web/lib/sak/gateway.ex`) is a GenServer that owns the Node process via a `Port` and speaks newline-delimited JSON over stdio. Command and message shapes live in `gateway/src/protocol.ts`; the Elixir side is untyped maps, so **change both sides together**.

- Requests: `Sak.Gateway.request(type, params)` sends `{id, type, ...params}`; the reply is matched by `id` (`{:ok, result}` / `{:error, msg}`). Commands are processed serially on the gateway side (`main.ts` queue).
- Pushes: `snapshot` and `events` messages are broadcast on PubSub topic `Sak.Gateway.conversation_topic(id)`; a conversation only streams after an `attach` command. After the gateway (re)starts it broadcasts `:gateway_started` on `started_topic/0` so LiveViews re-attach.
- `Gateway` class (`gateway/src/gateway.ts`) dispatches commands onto the pi-durable `Harness`: create/fork/submit/abort/attach/detach, model switching, personas, and per-conversation metadata.
- Per-conversation metadata (name, persona, `active|archived|deleted` state) is a durable doc defined in `gateway/src/meta.ts`; deletion is a soft state, filtered out of `list_conversations`.
- Gateway config is env-driven (`gateway/src/config.ts`: `SAK_BASE_URL`, `SAK_MODEL`, `SAK_DB`, `SAK_CWD`, `SAK_CONFIG_DIR`, `SAK_API_KEY`). The default model endpoint is an OpenAI-compatible server at `localhost:1234/v1`. Web's `config.exs` sets how the gateway is launched (`node src/main.ts` with `cd: gateway/`); `config/test.exs` sets `gateway: nil` so tests don't spawn it.
- Personas are markdown files loaded from `$SAK_CONFIG_DIR/personas` (default `~/.config/sak/personas`), with a builtin `default`. Claude-style tool names are aliased in `personas.ts`. The `codemode` tool (`codemode.ts`) runs a sandboxed script that calls the other tools.

### Web side

- `Sak.Chat` (`web/lib/sak/chat.ex`) is a pure model that folds the gateway's snapshot and event batches into display items and returns LiveView stream ops (`{:insert, item}`, `{:delete, item}`, `:reset`). Keep it free of socket concerns.
- `SakWeb.ChatLive` is the single LiveView. Its behavior is split into modules under `web/lib/sak_web/live/chat_live/` (`Keys`, `Sessions`, `Entries`, `Items`, `NewSession`, `Models`, `Search`, `Mention`, `Command`, `Confirm`, `Manage`, `Events`, `Render`), each taking and returning the socket. `ChatLive` itself mostly routes `handle_info`/`handle_event` to them.
- Keyboard handling is layered: the JS `key_router` hook decides which keys go to the server, and `ChatLive.Keys` routes by the active modal (help, wizard, command palette, confirm, search, ...) or falls back to global keys. Keybindings and help text come from `Sak.Keybindings` / `Sak.Help` / `Sak.Hints`.
- `Sak.*` modules hold the pure logic (fuzzy match, file index/picker, command parsing, new-session wizard state, session/entry row building, markdown via `mdex`); `SakWeb.*Components` / `Dialogs` / `Overlays` / `WizardOverlay` are the presentation layer.
- Tests swap the gateway for a fake: `test/support/fake_gateway_client.ex` (and `fake_gateway.exs` for a fake process) via the `:fake_gateway_replies` app env.

## Repo notes

- `web/priv/static/assets/` is gitignored build output; digested files elsewhere in `web/priv/static/` show up as untracked after `mix assets.deploy`.
- `*.sqlite*` files (the conversation DB, created in the gateway's working directory) are gitignored.
