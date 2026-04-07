import AppKit
import SwiftUI

let WINDOW_W: CGFloat = 110

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let store = StatsStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeStat")

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: WINDOW_W, height: COLLAPSED_H),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Default position: top-right, below notch safe zone
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - WINDOW_W - 16
            let y = screen.visibleFrame.maxY - COLLAPSED_H - 16
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Restore saved position
        if let saved = UserDefaults.standard.string(forKey: "panelOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { panel.setFrameOrigin(NSPoint(x: parts[0], y: parts[1])) }
        }

        let hostView = NSHostingView(
            rootView: HUDView(onToggle: { [weak self] expanded in
                self?.resize(expanded: expanded)
            }).environmentObject(store)
        )
        hostView.frame = panel.contentView!.bounds
        hostView.autoresizingMask = [.width, .height]
        panel.contentView = hostView

        panel.makeKeyAndOrderFront(nil)
    }

    func resize(expanded: Bool) {
        let newH = expanded ? EXPANDED_H : COLLAPSED_H
        var frame = panel.frame
        // Keep the top edge fixed; grow downward
        let topEdge = frame.origin.y + frame.height
        frame.size.height = newH
        frame.origin.y    = topEdge - newH
        // Save position
        UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y + newH)", forKey: "panelOrigin")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.makeKeyAndOrderFront(nil); return false
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
