import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator: ObservableObject {
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func showSettings(monitor: BatteryMonitor) {
        if let settingsWindow, settingsWindow.isVisible {
            bringToFront(settingsWindow)
            return
        }

        let window = FloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "BatteryVakt – Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        let hostingView = NSHostingView(
            rootView: SettingsView(
                settings: monitor.settings,
                refresh: monitor.refreshNow,
                showAbout: { [weak self, weak monitor] in
                    guard let monitor else { return }
                    self?.showAbout(monitor: monitor)
                }
            )
                .environmentObject(monitor)
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.setContentSize(hostingView.fittingSize)
        window.center()
        settingsWindow = window
        bringToFront(window)
    }

    func showAbout(monitor: BatteryMonitor) {
        if let aboutWindow, aboutWindow.isVisible {
            bringToFront(aboutWindow)
            return
        }

        let window = FloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About BatteryVakt"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.contentView = NSHostingView(rootView: AboutView(monitor: monitor))
        window.center()
        aboutWindow = window
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.unhide(nil)
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }
}

private final class FloatingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
