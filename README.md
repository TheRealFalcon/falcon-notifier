# falcon-notifier

A small native macOS Dock and menu bar app. One compiled Swift executable, AppKit and
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
Codex has an outstanding approval or input request. Click the dot for counts,
reconnect, and quit. The Dock icon opens a status window with a server address
field and **Connect** button. Its badge shows `!` when input is needed, `…` while
working, and `?` while disconnected; idle sessions have no badge. Right-click
the Dock icon to show the window or reconnect.

While red or yellow, the entire menu bar also gets a matching translucent tint.
The tint disappears when green or disconnected. It is click-through and cannot
take keyboard focus, so menus and the status button still work. It follows display
and Space changes, includes notched displays, and hides when macOS reports the
menu bar hidden. With separate Spaces per display enabled, each display is tinted.
This is a 32% opacity overlay, rather than a system theme change: macOS's existing
text and icons remain visible through the color, and their appearance is tinted too.

## Build and run

Requires macOS 13+ and Swift 6+ (Apple's Command Line Tools). Builds for the
current Mac's architecture.

```sh
sh scripts/build.sh
open dist/falcon-notifier.app
```

The release app is self-contained; you can copy `dist/falcon-notifier.app` to
`~/Applications`. For automatic startup, add that copy under System Settings →
General → Login Items. Launching the app opens its status window and connects
automatically. Closing the window keeps the app running; click its Dock icon to
reopen it, or use **Quit Falcon Notifier** (⌘Q) to stop it.

## Start the Codex server

Requires the Codex CLI with `app-server --listen` and `--remote` support.
falcon-notifier connects to a separately running server; it doesn't start or stop
one. By default it observes `ws://127.0.0.1:45999`.

Start the server in a dedicated terminal and leave it running:

```sh
codex app-server --listen ws://127.0.0.1:45999
```

In another terminal, switch to your project directory and start a session on that
server:

```sh
codex --remote ws://127.0.0.1:45999 --cd "$PWD"
```

To resume an existing session instead:

```sh
codex --remote ws://127.0.0.1:45999 --cd "$PWD" resume
```

Keep the server running while using Codex and falcon-notifier. If the server is
unavailable, the dot is gray and the notifier retries automatically. Adding the
notifier to Login Items starts only the notifier; start the server separately.
Sessions on other servers or standalone CLI processes aren't visible here.

To change the endpoint, enter a WebSocket URL in the status window and click
**Connect**. The app saves that address for future launches, including launches
from Finder or the Dock. You can also pass `--server` or set
`CODEX_APP_SERVER_URL` in the launching process's environment; these override the
saved address (`--server` takes priority). A Finder launch doesn't inherit your
shell's environment. To launch a fresh instance with an explicit address:

```sh
open -n dist/falcon-notifier.app --args --server ws://127.0.0.1:45999
```

## Checks

```sh
node scripts/integration-test.mjs
dist/falcon-notifier.app/Contents/MacOS/falcon-notifier --once
```

`--once` prints one JSON status and exits (nonzero when unavailable); `--watch`
prints changes. These terminal modes do not show a Dock icon or window and ignore
the saved GUI address; use `--server` or `CODEX_APP_SERVER_URL` to override their
default endpoint. The integration test needs Node 18+ only for its local fixture,
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
