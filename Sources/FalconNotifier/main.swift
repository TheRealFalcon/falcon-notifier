import AppKit
import FalconNotifierCore

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print("""
    Usage: falcon-notifier [--server ws://127.0.0.1:45999] [--once | --watch]
      Default: Dock and menu bar app. --once prints a JSON status and exits; --watch streams changes.
      Server default: CODEX_APP_SERVER_URL, saved address (GUI only), then ws://127.0.0.1:45999.
    """)
    exit(0)
}
let headless = arguments.contains("--once") || arguments.contains("--watch")
var endpoint = ProcessInfo.processInfo.environment["CODEX_APP_SERVER_URL"]
    ?? (headless ? nil : UserDefaults.standard.string(forKey: "serverURL"))
    ?? "ws://127.0.0.1:45999"
if let index = arguments.firstIndex(of: "--server"), arguments.indices.contains(index + 1) {
    endpoint = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
}
guard arguments.allSatisfy({ ["--once", "--watch"].contains($0) }),
      !(arguments.contains("--once") && arguments.contains("--watch")),
      let url = URL(string: endpoint), ["ws", "wss"].contains(url.scheme), url.host != nil else {
    FileHandle.standardError.write(Data("Invalid arguments or WebSocket URL. Use --help.\n".utf8))
    exit(2)
}

if headless {
    let source = CodexSource(url: url)
    source.onChange = { indicator in
        let data = try! JSONEncoder().encode(indicator)
        FileHandle.standardOutput.write(data + Data([10]))
        if arguments.contains("--once") { exit(indicator.level == .unavailable ? 1 : 0) }
    }
    source.start()
    dispatchMain()
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = AppDelegate(serverURL: url)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
