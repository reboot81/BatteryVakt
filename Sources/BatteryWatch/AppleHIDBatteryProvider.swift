import Foundation
import IOKit.hid

struct AppleHIDBatteryProvider: BatteryProvider {
    func devices() throws -> [BatteryDevice] {
        var interfaces: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceNameMatching("IOHIDInterface"),
            &interfaces
        ) == KERN_SUCCESS else {
            throw BatteryProviderError.hidUnavailable
        }
        defer { IOObjectRelease(interfaces) }

        var found: [String: BatteryDevice] = [:]
        var interface = IOIteratorNext(interfaces)
        while interface != 0 {
            var descendants: io_iterator_t = 0
            if IORegistryEntryCreateIterator(
                interface,
                kIOServicePlane,
                IOOptionBits(kIORegistryIterateRecursively),
                &descendants
            ) == KERN_SUCCESS {
                var entry = IOIteratorNext(descendants)
                while entry != 0 {
                    if let device = batteryDevice(from: entry) {
                        found[device.id] = device
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(descendants)
                }
                IOObjectRelease(descendants)
            }
            IOObjectRelease(interface)
            interface = IOIteratorNext(interfaces)
        }
        return Array(found.values)
    }

    private func batteryDevice(from entry: io_registry_entry_t) -> BatteryDevice? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any],
              let battery = values["BatteryPercent"] as? NSNumber,
              (values["HasBattery"] as? NSNumber)?.boolValue != false else {
            return nil
        }
        let name = values["Product"] as? String ?? "Apple HID device"
        let address = stringValue(values["DeviceAddress"])
        let serialNumber = stringValue(values[kIOHIDSerialNumberKey as String])
            ?? stringValue(values["SerialNumberString"])
            ?? stringValue(values["SerialNumber"])
        let vendor = (values["VendorID"] as? NSNumber)?.intValue ?? 0
        let product = (values["ProductID"] as? NSNumber)?.intValue ?? 0
        let identifier = address ?? "apple-hid:\(vendor):\(product):\(name)"
        return BatteryDevice(
            id: identifier,
            name: name,
            batteryPercent: battery.intValue,
            isConnected: true,
            source: .appleHID,
            isCharging: (values["IsCharging"] as? NSNumber)?.boolValue,
            serialNumber: serialNumber,
            bluetoothAddress: address
        )
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}
