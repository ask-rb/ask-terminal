# Changelog

All notable changes to ask-terminal are documented here, following
the keep-a-changelog format.

## [Unreleased]

## [0.2.0] - 2026-08-12

### Changed

- **The protocol client moved to `ask-session-client`** — `Client` and
  `Host` now live in the shared gem; ask-terminal keeps thin aliases
  (`Ask::Terminal::Client` = `Ask::SessionClient::Client`), so existing
  references keep working. The board app, bots, and CI use the same
  client.
## [0.1.2] - 2026-08-11

### Added

- **Spawned hosts are multi-client attachable by default** — `ask` starts
  the host with a unix socket (unique per spawn under
  `~/.ask-app-server/sockets/`, or `ASK_APP_SERVER_SOCKET` when set) and
  prints the path on startup, so the web console, bots, or a second
  terminal can attach to the same live sessions. `Host.spawn(socket:)`
  controls it: `true` (default), a custom path, or `false` to disable.

## [0.1.1] - 2026-08-11

### Changed

- **The command is now `ask`** — the terminal client's primary executable
  is the short brand name; `ask-terminal` remains installed as a long
  alias. Both behave identically. CLI logic moved into
  `Ask::Terminal::CLI`.

## [0.1.0] - 2026-08-11

### Added

- **`Client`** — a thin NDJSON protocol client over the host's stdio or a
  unix socket: request/response correlation by id, notification queue,
  protocol error handling, and connection-close semantics (sentinel
  notification + `ConnectionClosed` on pending requests).
- **`Host`** — spawns `ask-app-server` as a subprocess (`Gem.bin_path`,
  PATH fallback) or attaches to a running host over its unix socket.
- **`Renderer`** — canonical session events rendered as ANSI terminal
  output: streaming model/thinking deltas, tool lifecycle with duration
  and truncated output, approval and plan interactions, todos progress,
  turn lifecycle.
- **`Repl`** — the interactive loop: prompt → `session/send` → stream
  events → resolve approvals (y/N) and plan proposals (y/N) inline via the
  canonical `interaction/*` and `plan/*` methods → prompt again. Commands:
  `/approve`, `/reject`, `/plan-approve`, `/plan-reject`, `/abort`,
  `/status`, `/sessions`, `/exit`; Ctrl-C aborts the running turn.
- **`ask-terminal` executable** — `--host stdio|socket`, `--socket PATH`,
  `--workspace`, `--model`, `--approval`.
- **Test suite** — 37 tests: protocol client against a scripted peer,
  renderer coverage, repl interaction flows (approval/plan/commands), and
  end-to-end integration over a real in-process SocketServer host
  (handshake, session lifecycle, approval streaming, two clients sharing
  one session).
