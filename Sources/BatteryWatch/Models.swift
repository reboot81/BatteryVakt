import Foundation

enum BatterySource: String, Sendable {
    case appleHID = "Apple HID"
    case logitechHIDPP = "Logitech HID++"
}

struct BatteryDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let batteryPercent: Int
    let isConnected: Bool
    let source: BatterySource
    let isCharging: Bool?
    let serialNumber: String?
    let bluetoothAddress: String?

    var displayStatus: String {
        let charge = isCharging == true ? "charging" : "battery"
        return "\(batteryPercent)% \(charge)"
    }

    var identityDetails: String? {
        var details: [String] = []
        if let serialNumber, !serialNumber.isEmpty { details.append("SN: \(serialNumber)") }
        if let bluetoothAddress, !bluetoothAddress.isEmpty {
            details.append("MAC: \(bluetoothAddress.replacingOccurrences(of: "-", with: ":").uppercased())")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    var menuDescription: String {
        "\(name) — \(displayStatus)"
    }
}

enum BatterySeverity: Int, Comparable {
    case normal, low, critical

    static func < (lhs: BatterySeverity, rhs: BatterySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case lowestBattery
    case rotateDevices
    case discreetIcon

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lowestBattery: "Lowest battery"
        case .rotateDevices: "Rotate devices"
        case .discreetIcon: "Discreet icon"
        }
    }

    var explanation: String {
        switch self {
        case .lowestBattery: "Shows the lowest battery percentage."
        case .rotateDevices: "Cycles through connected devices."
        case .discreetIcon: "Shows a muted battery symbol only."
        }
    }
}
