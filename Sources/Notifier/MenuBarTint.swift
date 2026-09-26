import AppKit

/// A translucent strip above the system menu bar. It never takes focus or clicks.
@MainActor
final class MenuBarTint: NSObject {
    private var panels: [NSPanel] = []
    private var color: NSColor?
    private var visibilityTimer: Timer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(rebuild),
                name: name, object: nil)
        }
    }

    func setColor(_ color: NSColor?) {
        guard self.color != color else { return }
        self.color = color
        if color == nil {
            visibilityTimer?.invalidate()
            visibilityTimer = nil
            panels.forEach { $0.orderOut(nil) }
            panels.removeAll()
            return
        }
        rebuild()
        if visibilityTimer == nil {
            // Track auto-hide/fullscreen visibility even when the Codex status is unchanged.
            let timer = Timer(timeInterval: 0.5, target: self,
                selector: #selector(updateVisibility), userInfo: nil, repeats: true)
            timer.tolerance = 0.15
            RunLoop.main.add(timer, forMode: .common)
            visibilityTimer = timer
        }
    }

    @objc private func rebuild() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        guard let color else { return }
        let screens = NSScreen.screensHaveSeparateSpaces ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let reservedHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness,
                             reservedHeight <= 64 ? reservedHeight : 0)
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                               width: screen.frame.width, height: height)
            let panel = TintPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
            panel.title = "Notifier menu bar tint"
            panel.isOpaque = false
            panel.backgroundColor = color.withAlphaComponent(0.32)
            panel.hasShadow = false
            // Below dropdown menus, above the bar's opaque background. A solid fill
            // here would hide its text; transparency preserves the real menu contents.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.setFrame(frame, display: false)
            panels.append(panel)
        }
        updateVisibility()
    }

    @objc private func updateVisibility() {
        let visible = NSMenu.menuBarVisible()
        for panel in panels {
            if visible && !panel.isVisible { panel.orderFrontRegardless() }
            else if !visible && panel.isVisible { panel.orderOut(nil) }
        }
    }
}

private final class TintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit normally constrains windows to the area *below* the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
