import AppKit
import FalconNotifierCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var source: CodexSource
    private var serverURL: URL
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private let menuBarTint = MenuBarTint()
    private let summaryItem = NSMenuItem(title: "Connecting to Codex…", action: nil, keyEquivalent: "")
    private let endpointItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Connecting to Codex…")
    private let statusImage = NSImageView()
    private let serverField = NSTextField(string: "")
    private let connectionLabel = NSTextField(wrappingLabelWithString: "")

    init(serverURL: URL) {
        self.serverURL = serverURL
        self.source = CodexSource(url: serverURL)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureWindow()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let menu = NSMenu()
        menu.addItem(summaryItem)
        menu.addItem(endpointItem)
        menu.addItem(.separator())
        menu.addItem(actionItem("Show Falcon Notifier", action: #selector(showWindow)))
        menu.addItem(actionItem("Reconnect", action: #selector(reconnect), key: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Falcon Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        startObserving()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: summaryItem.title, action: nil, keyEquivalent: ""))
        menu.addItem(actionItem("Show Falcon Notifier", action: #selector(showWindow)))
        menu.addItem(actionItem("Reconnect", action: #selector(reconnect)))
        return menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        source.stop()
        menuBarTint.setColor(nil)
    }

    private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func configureMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Falcon Notifier")
        appMenu.addItem(NSMenuItem(title: "About Falcon Notifier", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Falcon Notifier", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Falcon Notifier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(actionItem("Show Falcon Notifier", action: #selector(showWindow), key: "0"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    private func configureWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Falcon Notifier"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Falcon Notifier")
        let title = NSTextField(labelWithString: "Falcon Notifier")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Your Codex sessions, at a glance.")
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        let header = NSStackView(views: [icon, heading])
        header.spacing = 14

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        let status = NSStackView(views: [statusImage, statusLabel])
        status.spacing = 10
        serverField.stringValue = serverURL.absoluteString
        serverField.placeholderString = "ws://127.0.0.1:45999"
        serverField.setAccessibilityLabel("Server address")
        serverField.target = self
        serverField.action = #selector(connect)
        let connectButton = NSButton(title: "Connect", target: self, action: #selector(connect))
        connectButton.keyEquivalent = "\r"
        let connection = NSStackView(views: [serverField, connectButton])
        connection.spacing = 8
        connectionLabel.textColor = .secondaryLabelColor
        connectionLabel.font = .systemFont(ofSize: 12)
        let hint = NSTextField(wrappingLabelWithString: "Start your Codex server separately. Closing this window keeps the notifier running in the Dock and menu bar.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let stack = NSStackView(views: [header, status, NSTextField(labelWithString: "Codex server"), connection, connectionLabel, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            statusImage.widthAnchor.constraint(equalToConstant: 18),
            statusImage.heightAnchor.constraint(equalToConstant: 18),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            connection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            connectionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func showWindow() {
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func connect() {
        let endpoint = serverField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), ["ws", "wss"].contains(url.scheme),
              let host = url.host, !host.isEmpty else {
            connectionLabel.stringValue = "Enter a WebSocket address, such as ws://127.0.0.1:45999."
            return
        }
        source.onChange = nil
        source.stop()
        serverURL = url
        serverField.stringValue = endpoint
        UserDefaults.standard.set(endpoint, forKey: "serverURL")
        source = CodexSource(url: url)
        startObserving()
    }

    @objc private func reconnect() {
        source.stop()
        startObserving()
    }

    private func startObserving() {
        endpointItem.title = serverURL.absoluteString
        connectionLabel.stringValue = "Observing \(serverURL.absoluteString) • reconnects automatically"
        source.onChange = { [weak self] indicator in self?.render(indicator) }
        render(Indicator(level: .unavailable, summary: "Connecting to Codex…"))
        source.start()
    }

    private func render(_ indicator: Indicator) {
        let color: NSColor
        let badge: String?
        switch indicator.level {
        case .attention:
            color = NSColor(srgbRed: 1, green: 92/255, blue: 92/255, alpha: 1)
            badge = "!"
        case .busy:
            color = NSColor(srgbRed: 1, green: 215/255, blue: 64/255, alpha: 1)
            badge = "…"
        case .ready:
            color = NSColor(srgbRed: 105/255, green: 240/255, blue: 174/255, alpha: 1)
            badge = nil
        case .unavailable:
            color = .systemGray
            badge = "?"
        }
        NSApp.dockTile.badgeLabel = badge
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
        statusLabel.stringValue = indicator.summary
        statusImage.image = image
    }
}
