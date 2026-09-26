# Notifier

A small native macOS menu bar app. One compiled Swift executable, AppKit and
Foundation only, with no third-party dependencies or runtime scripts.

The dot reflects **all loaded sessions** on your shared Codex app-server,
including child sessions:

| Color | Meaning |
| --- | --- |
| Red | At least one session needs approval or interactive input |
| Yellow | At least one session is working, and none needs input |
| Green | No session needs input or is working (including zero sessions) |
| Gray | Connecting, disconnected, or unable to read status |

Finished sessions waiting for your *next prompt* count as idle/green. Red means
Codex has an outstanding approval or input request. Colors match `codex-status`'s
Stream Deck implementation. Click the dot for counts, reconnect, and quit.

## Build and run

Requires macOS 13+ and Swift 6+ (Apple's Command Line Tools). Builds for the
current Mac's architecture.

```sh
sh scripts/build.sh
open dist/Notifier.app
```

The release app is self-contained; you can copy `dist/Notifier.app` to
`~/Applications`. For automatic startup, add that copy under System Settings →
General → Login Items. There is no Dock icon or main window.

By default it observes `ws://127.0.0.1:45999`, so keep starting Codex as usual:

```sh
codex --remote ws://127.0.0.1:45999 --cd "$PWD" resume
```

Your Stream Deck plugin currently starts that server. Notifier connects to it;
it doesn't start or stop the server. If you stop using the Stream Deck plugin,
run the same server yourself with `codex app-server --listen ws://127.0.0.1:45999`.
Sessions on other servers or standalone CLI processes aren't visible here.

To override the endpoint, pass `--server` or set `CODEX_APP_SERVER_URL` in the
launching process's environment. A Finder launch doesn't inherit your shell's
environment. For example:

```sh
open dist/Notifier.app --args --server ws://127.0.0.1:45999
```

## Checks

```sh
node scripts/integration-test.mjs
dist/Notifier.app/Contents/MacOS/Notifier --once
```

`--once` prints one JSON status and exits (nonzero when unavailable); `--watch`
prints changes. The integration test needs Node 18+ only for its local fixture,
and tests the compiled release executable without touching real Codex sessions.
It covers both approval and input waits, priority across sessions, pagination,
updates and closures during a snapshot, missed notifications, and reconnection.

## How it works / extending it

`CodexSource` is a read-only WebSocket JSON-RPC client. It initializes a connection,
enumerates `thread/loaded/list` with pagination, and reads each loaded thread's
status without turns. It handles `thread/status/changed` immediately and
reconciles every three seconds to discover sessions and recover missed events.
New notifications take precedence over an in-flight snapshot. Requests time out
after ten seconds; failed connections retry after five seconds. The server may
retain idle threads after a terminal closes; these remain green.

The observer never resumes threads or answers approval requests. The protocol is
documented in [Codex App Server](https://developers.openai.com/codex/app-server).
That interface is experimental, so future Codex updates may require adjustments.

The menu bar renderer consumes an `Indicator` (level, summary, SF Symbol name)
from a `StatusSource`. To add another signal later, implement that small protocol
and select it in `main.swift`, or compose multiple sources into one indicator.
Codex state and networking are separate from the AppKit presentation.

[SwiftBar](https://swiftbar.github.io/SwiftBar/) could also host a persistent
compiled plugin. This app keeps the installation to a single native process.
