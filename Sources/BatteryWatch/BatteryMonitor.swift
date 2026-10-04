import Foundation
import AppKit
import IOKit.hid
import UserNotifications

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var devices: [BatteryDevice] = []
    @Published private(set) var discoveredDevices: [BatteryDevice] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var ntfyTestStatus = ""
    @Published var isNtfyInformationPresented = false
    @Published var isLogitechAccessInformationPresented = false
    @Published private(set) var mxVerticalDetected = false
    @Published private(set) var logitechHIDPPDetected = false
    @Published private(set) var boltReceiverDetected = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var boltStatus = ""
    let settings = MonitorSettings()

    private var timer: Timer?
    private var isRefreshing = false
    private var rotationTimer: Timer?
    @Published private var rotationIndex = 0
    private var severities: [String: BatterySeverity] = [:]
    private let appleProvider = AppleHIDBatteryProvider()
    private let boltProvider = LogitechBoltBatteryProvider()
    private let logitechProvider = LogitechHIDPPBatteryProvider()
    private let notificationDelegate = BatteryVaktNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Task { await refreshNotificationAuthorization(); refreshNow() }
        restartPolling()
        restartRotation()
    }

    var menuBarTitle: String {
        guard let lowest = devices.min(by: { $0.batteryPercent < $1.batteryPercent }) else { return "Battery" }
        return devices.count == 1 ? "\(lowest.batteryPercent)%" : "\(lowest.batteryPercent)% · \(devices.count)"
    }

    var menuBarSymbol: String {
        guard let lowest = devices.min(by: { $0.batteryPercent < $1.batteryPercent }) else { return "battery.100percent" }
        switch settings.severity(for: lowest.batteryPercent) {
        case .critical: return "battery.0percent"
        case .low: return "battery.25percent"
        case .normal: return "battery.100percent"
        }
    }

    var menuBarDevice: BatteryDevice? {
        guard !devices.isEmpty else { return nil }
        switch settings.menuBarDisplayMode {
        case .lowestBattery, .discreetIcon:
            return devices.min(by: { $0.batteryPercent < $1.batteryPercent })
        case .rotateDevices:
            return devices[rotationIndex % devices.count]
        }
    }

    var hasAlert: Bool {
        guard let device = menuBarDevice else { return false }
        return settings.severity(for: device.batteryPercent) > .normal
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let useLogitechHIDPP = settings.logitechHIDPPEnabled
        Task.detached { [appleProvider, boltProvider, logitechProvider] in
            let mxVerticalDetected = LogitechHIDPPBatteryProvider.mxVerticalIsConnected()
            let boltReceiverDetected = LogitechBoltBatteryProvider.boltReceiverIsConnected()
            let inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            let providers: [any BatteryProvider] = useLogitechHIDPP
                ? [appleProvider, boltProvider, logitechProvider]
                : [appleProvider]
            var result: [BatteryDevice] = []
            var boltUnavailable = false
            var mxVerticalUnavailable = false
            var logitechErrors: [String] = []
            for provider in providers {
                do {
                    result += try provider.devices()
                } catch {
                    if provider is LogitechBoltBatteryProvider { boltUnavailable = true }
                    if provider is LogitechHIDPPBatteryProvider { mxVerticalUnavailable = true }
                    if provider is LogitechBoltBatteryProvider || provider is LogitechHIDPPBatteryProvider {
                        let label = provider is LogitechBoltBatteryProvider ? "Logi Bolt" : "MX Vertical"
                        logitechErrors.append("\(label): \(error.localizedDescription)")
                    }
                }
            }
            await MainActor.run {
                self.isRefreshing = false
                self.mxVerticalDetected = mxVerticalDetected
                self.boltReceiverDetected = boltReceiverDetected
                self.logitechHIDPPDetected = mxVerticalDetected || boltReceiverDetected
                self.inputMonitoringGranted = inputMonitoringGranted
                if mxVerticalUnavailable || boltUnavailable {
                    self.boltStatus = inputMonitoringGranted
                        ? "BatteryVakt has Input Monitoring access, but HID++ battery reading failed: \(logitechErrors.joined(separator: " "))"
                        : "BatteryVakt detected Logitech hardware, but Input Monitoring is not allowed. Allow BatteryVakt, then refresh."
                } else {
                    self.boltStatus = ""
                }
                self.apply(result)
            }
        }
    }

    func restartPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.pollIntervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    func restartRotation() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.rotationIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotationIndex += 1 }
        }
    }

    func setMonitoring(_ device: BatteryDevice, enabled: Bool) {
        settings.setMonitoring(device, enabled: enabled)
        rebuildMonitoredDevices(from: discoveredDevices, announceConnectionChanges: false)
    }

    func testNtfy() async throws {
        guard let topic = settings.configuredNtfyTopic else { throw NtfyError.invalidTopic }
        do {
            try await NtfyProvider(topic: topic).send(
                title: "TEST BatteryVakt",
                message: "Test notification from \(settings.ntfyDeviceName).",
                priority: 3,
                tags: ["battery", "test"]
            )
            ntfyTestStatus = "Testmeddelande skickat"
        } catch {
            ntfyTestStatus = error.localizedDescription
            throw error
        }
    }

    func clearNtfyTestStatus() {
        ntfyTestStatus = ""
    }

    func showNtfyInformation() {
        isNtfyInformationPresented = true
    }

    func hideNtfyInformation() {
        isNtfyInformationPresented = false
    }

    func testLocalNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "TEST BatteryVakt"
        content.body = "This is a local notification test."
        content.sound = .default
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "local-test.\(UUID())", content: content, trigger: nil)
        )
    }

    func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }

    func openNotificationSettings() {
        Task {
            // This call is also how macOS registers an app in Notification Settings.
            // macOS only presents its consent dialog while authorization is undecided.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshNotificationAuthorization()
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    func testBatteryAlert(severity: BatterySeverity) {
        let device = devices.min(by: { $0.batteryPercent < $1.batteryPercent })
            ?? BatteryDevice(id: "test", name: "BatteryVakt test device", batteryPercent: severity == .critical ? settings.criticalThreshold : settings.lowThreshold, isConnected: true, source: .appleHID, isCharging: false, serialNumber: nil, bluetoothAddress: nil)
        let label = severity == .critical ? "critical" : "low"
        let content = UNMutableNotificationContent()
        content.title = "TEST Battery \(label)"
        content.body = "\(device.name) is at \(device.batteryPercent)%."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "battery-test.\(severity.rawValue).\(UUID())", content: content, trigger: nil)
        )
        if severity == .critical {
            showCriticalDialog(title: content.title, message: content.body)
        }
    }

    private func apply(_ latest: [BatteryDevice]) {
        discoveredDevices = latest.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        rebuildMonitoredDevices(from: latest, announceConnectionChanges: true)
    }

    private func rebuildMonitoredDevices(from latest: [BatteryDevice], announceConnectionChanges: Bool) {
        let previousDevices = devices
        let oldIDs = Set(previousDevices.map(\.id))
        let monitored = latest.filter(settings.monitors).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let newIDs = Set(monitored.map(\.id))
        devices = monitored
        lastChecked = .now
        lastError = latest.isEmpty
            ? (settings.logitechHIDPPEnabled
                ? "No battery devices found."
                : "No battery devices found. Enable Direct Logitech battery access to check an MX Vertical.")
            : (monitored.isEmpty ? "All detected devices are excluded from monitoring." : nil)

        for device in monitored {
            let severity = settings.severity(for: device.batteryPercent)
            let previous = severities[device.id] ?? .normal
            severities[device.id] = severity
            if severity > previous { notifyBattery(device, severity: severity) }
            if announceConnectionChanges && !oldIDs.contains(device.id) { notifyConnection(device, connected: true) }
        }
        if announceConnectionChanges {
            for removedID in oldIDs.subtracting(newIDs) {
                if let prior = previousDevices.first(where: { $0.id == removedID }) { notifyConnection(prior, connected: false) }
            }
        }
        for removedID in oldIDs.subtracting(newIDs) {
            severities.removeValue(forKey: removedID)
        }
    }

    private func notifyBattery(_ device: BatteryDevice, severity: BatterySeverity) {
        let content = UNMutableNotificationContent()
        content.title = severity == .critical ? "Battery critical" : "Battery low"
        content.body = "\(device.name) is at \(device.batteryPercent)%."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "battery.\(device.id).\(severity.rawValue)", content: content, trigger: nil))
        sendNtfyBatteryAlert(device, severity: severity)
        if severity == .critical {
            showCriticalDialog(title: content.title, message: content.body)
        }
    }

    private func sendNtfyBatteryAlert(_ device: BatteryDevice, severity: BatterySeverity) {
        guard let topic = settings.configuredNtfyTopic else { return }
        let critical = severity == .critical
        Task {
            try? await NtfyProvider(topic: topic).send(
                title: critical ? "Battery critical" : "Battery low",
                message: "\(device.name) on \(settings.ntfyDeviceName) is at \(device.batteryPercent)%.",
                priority: critical ? 5 : 4,
                tags: ["battery", critical ? "rotating_light" : "warning"]
            )
        }
    }

    private func notifyConnection(_ device: BatteryDevice, connected: Bool) {
        let content = UNMutableNotificationContent()
        content.title = connected ? "Battery device connected" : "Battery device disconnected"
        content.body = device.name
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "connection.\(device.id).\(UUID())", content: content, trigger: nil))
    }

    private func showCriticalDialog(title: String, message: String) {
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Jag förstår")
        alert.runModal()
    }
}

private final class BatteryVaktNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
