import Foundation
import ServiceManagement

@MainActor
final class MonitorSettings: ObservableObject {
    @Published var lowThreshold: Int { didSet { save() } }
    @Published var criticalThreshold: Int { didSet { save() } }
    @Published var pollIntervalMinutes: Int { didSet { save() } }
    @Published var loginItemEnabled: Bool { didSet { updateLoginItem() } }
    @Published var menuBarDisplayMode: MenuBarDisplayMode { didSet { save() } }
    @Published var rotationIntervalSeconds: Int { didSet { save() } }
    @Published var ntfyTopic: String { didSet { save() } }
    @Published var remoteDeviceName: String { didSet { save() } }
    @Published var logitechHIDPPEnabled: Bool { didSet { save() } }
    @Published private(set) var excludedDeviceIDs: Set<String>

    private let defaults = UserDefaults.standard
    private var isNormalizing = false

    init() {
        lowThreshold = defaults.object(forKey: "lowThreshold") as? Int ?? 35
        criticalThreshold = defaults.object(forKey: "criticalThreshold") as? Int ?? 5
        pollIntervalMinutes = defaults.object(forKey: "pollIntervalMinutes") as? Int ?? 15
        loginItemEnabled = SMAppService.mainApp.status == .enabled
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: "menuBarDisplayMode") ?? "") ?? .lowestBattery
        rotationIntervalSeconds = defaults.object(forKey: "rotationIntervalSeconds") as? Int ?? 5
        ntfyTopic = defaults.string(forKey: "ntfyTopic") ?? ""
        remoteDeviceName = defaults.string(forKey: "remoteDeviceName") ?? ""
        logitechHIDPPEnabled = defaults.bool(forKey: "logitechHIDPPEnabled")
        excludedDeviceIDs = Set(defaults.stringArray(forKey: "excludedDeviceIDs") ?? [])
    }

    func severity(for percent: Int) -> BatterySeverity {
        if percent <= criticalThreshold { return .critical }
        if percent <= lowThreshold { return .low }
        return .normal
    }

    func monitors(_ device: BatteryDevice) -> Bool {
        !excludedDeviceIDs.contains(device.id)
    }

    func setMonitoring(_ device: BatteryDevice, enabled: Bool) {
        if enabled {
            excludedDeviceIDs.remove(device.id)
        } else {
            excludedDeviceIDs.insert(device.id)
        }
        defaults.set(Array(excludedDeviceIDs), forKey: "excludedDeviceIDs")
    }

    var configuredNtfyTopic: String? {
        let clean = ntfyTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        return NtfyTopicValidator.validate(clean) == .valid ? clean : nil
    }

    var ntfyDeviceName: String {
        let clean = remoteDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? (Host.current().localizedName ?? "Mac") : clean
    }

    private func save() {
        guard !isNormalizing else { return }
        isNormalizing = true
        lowThreshold = min(max(lowThreshold, 1), 99)
        criticalThreshold = min(max(criticalThreshold, 0), lowThreshold)
        pollIntervalMinutes = min(max(pollIntervalMinutes, 1), 120)
        rotationIntervalSeconds = min(max(rotationIntervalSeconds, 1), 60)
        isNormalizing = false
        defaults.set(lowThreshold, forKey: "lowThreshold")
        defaults.set(criticalThreshold, forKey: "criticalThreshold")
        defaults.set(pollIntervalMinutes, forKey: "pollIntervalMinutes")
        defaults.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
        defaults.set(rotationIntervalSeconds, forKey: "rotationIntervalSeconds")
        defaults.set(ntfyTopic, forKey: "ntfyTopic")
        defaults.set(remoteDeviceName, forKey: "remoteDeviceName")
        defaults.set(logitechHIDPPEnabled, forKey: "logitechHIDPPEnabled")
    }

    private func updateLoginItem() {
        do {
            if loginItemEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
