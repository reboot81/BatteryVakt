import SwiftUI

@main
struct BatteryVaktApp: App {
    @StateObject private var monitor: BatteryMonitor
    @StateObject private var windows: WindowCoordinator

    init() {
        _monitor = StateObject(wrappedValue: BatteryMonitor())
        _windows = StateObject(wrappedValue: WindowCoordinator())
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(
                monitor: monitor,
                showSettings: { windows.showSettings(monitor: monitor) },
                showAbout: { windows.showAbout(monitor: monitor) }
            )
        }
        label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { windows.showSettings(monitor: monitor) }
            }
        }

    }
}
