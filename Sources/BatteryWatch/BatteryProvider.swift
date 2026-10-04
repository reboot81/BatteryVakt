import Foundation
import IOKit

protocol BatteryProvider: Sendable {
    func devices() throws -> [BatteryDevice]
}

enum BatteryProviderError: LocalizedError {
    case hidUnavailable
    case hidOpenFailed(IOReturn)
    case hidSetReportFailed(IOReturn)
    case unsupportedDevice
    case featureUnavailable
    case badResponse
    case timeout
    case hidCollectionUnavailable
    case protocolError(UInt8)
    case deviceReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .hidUnavailable: "The HID interface could not be opened."
        case .hidOpenFailed(let result): "IOHIDDeviceOpen failed (\(format(result)))."
        case .hidSetReportFailed(let result): "IOHIDDeviceSetReport failed (\(format(result)))."
        case .unsupportedDevice: "No supported Logitech HID++ device is connected."
        case .featureUnavailable: "This device does not expose the requested HID++ feature."
        case .badResponse: "The device returned an invalid HID++ response."
        case .timeout: "The device did not answer the HID++ request."
        case .hidCollectionUnavailable: "The hardware is connected, but its HID++ collection is unavailable."
        case .protocolError(let code): String(format: "HID++ returned error 0x%02X.", code)
        case .deviceReadFailed(let message): message
        }
    }

    private func format(_ result: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: result))
    }
}
