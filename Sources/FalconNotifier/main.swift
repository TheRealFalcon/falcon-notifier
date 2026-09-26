import AppKit
import FalconNotifierCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let source: any StatusSource
    private let serverURL: URL
    private var statusItem: NSStatusItem?
    private let menuBarTint = MenuBarTint()
    private let summaryItem = NSMenuItem(title: "Connecting to Codex…", action: nil, keyEquivalent: "")

    init(source: any StatusSource, serverURL: URL) {
        self.source = source
        self.serverURL = serverURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let menu = NSMenu()
        menu.addItem(summaryItem)
        menu.addItem(NSMenuItem(title: serverURL.absoluteString, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let reconnect = NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "r")
        reconnect.target = self
        menu.addItem(reconnect)
        menu.addItem(NSMenuItem(title: "Quit falcon-notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        source.onChange = { [weak self] indicator in self?.render(indicator) }
        render(Indicator(level: .unavailable, summary: "Connecting to Codex…"))
        source.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        source.stop()
        menuBarTint.setColor(nil)
    }

    @objc private func reconnect() {
        source.stop()
        render(Indicator(level: .unavailable, summary: "Connecting to Codex…"))
        source.start()
    }

    private func render(_ indicator: Indicator) {
        let color: NSColor
        switch indicator.level {
        case .attention: color = NSColor(srgbRed: 1, green: 92/255, blue: 92/255, alpha: 1)
        case .busy: color = NSColor(srgbRed: 1, green: 215/255, blue: 64/255, alpha: 1)
        case .ready: color = NSColor(srgbRed: 105/255, green: 240/255, blue: 174/255, alpha: 1)
        case .unavailable: color = .systemGray
        }
        menuBarTint.setColor(indicator.level == .attention || indicator.level == .busy ? color : nil)
        let symbol = NSImage(systemSymbolName: indicator.symbol, accessibilityDescription: indicator.summary)
            ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: indicator.summary)!
        let image = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color])))!
        image.isTemplate = false
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = indicator.summary
        statusItem?.button?.setAccessibilityLabel(indicator.summary)
        summaryItem.title = indicator.summary
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print("""
    Usage: falcon-notifier [--server ws://127.0.0.1:45999] [--once | --watch]
      Default: menu bar app. --once prints a JSON status and exits; --watch streams changes.
      Server default: CODEX_APP_SERVER_URL, then ws://127.0.0.1:45999.
    """)
    exit(0)
}
var endpoint = ProcessInfo.processInfo.environment["CODEX_APP_SERVER_URL"] ?? "ws://127.0.0.1:45999"
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

let source = CodexSource(url: url)
if arguments.contains("--once") || arguments.contains("--watch") {
    source.onChange = { indicator in
        let data = try! JSONEncoder().encode(indicator)
        FileHandle.standardOutput.write(data + Data([10]))
        if arguments.contains("--once") { exit(indicator.level == .unavailable ? 1 : 0) }
    }
    source.start()
    dispatchMain()
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate(source: source, serverURL: url)
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
