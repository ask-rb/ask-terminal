# ask-terminal

**The terminal client of the ask ecosystem.** An interactive terminal
coding agent that speaks the canonical
[ask-session-protocol](https://github.com/ask-rb/ask-session-protocol) and
nothing else — no runtime, no sessions, no tools. The host
(ask-app-server) owns all of it; this client just renders events and
sends requests.

```
ask> fix the failing test in spec/models
› bash grep -rn "failing" spec/
  └ bash (120ms)
    ...
── turn completed ──
```

## Why this exists

The ask ecosystem's architecture is *one session host, one canonical
protocol, many thin clients*. ask-terminal is the first client and the
proof: it can attach to the same live sessions as the web console, a bot,
or an IDE — each client receives every event exactly once via its own
delivery cursor, and any client can resolve an approval or a plan proposal
by id.

## Usage

Two ways to reach a host (the command is `ask`; `ask-terminal` is the long
alias — both are installed by the gem):

```bash
# Spawn a host over stdio — it also exposes a unix socket for
# multi-client attach, and prints the path on startup:
ask
#   host socket: ~/.ask-app-server/sockets/4f3a9c2b1d0e8f7a.sock

# Attach to an already-running host over its unix socket (multi-client)
ask --socket ~/.ask-app-server/sockets/4f3a9c2b1d0e8f7a.sock

# Options
ask --workspace ~/code/myapp --model deepseek-v4-flash --approval on_request
```

Every spawned host is attachable: the web console, a bot, or a second
terminal can connect to the same live sessions (`ASK_APP_SERVER_SOCKET`
pins the path; `Host.spawn(socket: false)` disables it).

| Flag | Default | Description |
|---|---|---|
| `--host MODE` | `stdio` | `stdio` (spawn the host) or `socket` (attach) |
| `--socket PATH` | — | Attach to a running host (implies `--host socket`) |
| `-w, --workspace DIR` | current dir | Workspace for `session/create` |
| `--model MODEL` | host default | Model identifier |
| `--approval MODE` | `on_request` | `on_request` \| `off` \| `auto` |

## Interactive commands

| Command | Description |
|---|---|
| `/approve [id]` | Approve a pending approval (all when no id) |
| `/reject [id]` | Reject a pending approval (all when no id) |
| `/plan-approve` · `/plan-reject` | Resolve the pending plan proposal |
| `/abort` | Abort the running turn |
| `/status` | Show workspace and pending interactions |
| `/sessions` | List host sessions |
| `/exit` | Quit |

Approvals and plan proposals also resolve inline: when the host pauses a
turn, the terminal asks `Approve bash (act_1)? [y/N]` and resolves through
the canonical `interaction/approve` / `plan/approve` methods — the exact
requests any other client would make.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  ask-app-server (THE HOST — separate process)          │
│  sessions · events · approvals · plan · tools          │
└──────────────▲───────────────────────────┬─────────────┘
               │ canonical protocol        │
   ┌───────────┴──────────┐    ┌───────────▼─────────────┐
   │  ask-terminal        │    │  web console · bots ·   │
   │  (this client)       │    │  IDE — any client       │
   └──────────────────────┘    └─────────────────────────┘
```

* `Client` — NDJSON protocol over the host's stdio or a unix socket;
  request/response correlation, notification queue, connection-close
  handling.
* `Host` — spawns `ask-app-server` (`Gem.bin_path`) or connects to its
  socket.
* `Renderer` — canonical events → ANSI output (streaming deltas, tool
  lifecycle, approvals, plans, todos).
* `Repl` — the interactive loop: prompt → `session/send` → stream events
  → resolve interactions inline → prompt again.

## Development

```bash
bundle install
bundle exec rake test
```

## License

MIT
