import Foundation
import IOKit.hid
import IOBluetooth

/// Selects the same vendor collections as OpenLogi's macOS transport.
private final class LogitechInventory: @unchecked Sendable {
    static let shared = LogitechInventory()
    private let manager: IOHIDManager
    private let queue = DispatchQueue(label: "BatteryVakt.HIDDiscovery")

    private init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey as String: 0x046D] as CFDictionary)
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerActivate(manager)
    }

    func devices(productID: Int) -> [IOHIDDevice] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int == productID
        }
    }

    static func longOnly(_ device: IOHIDDevice) -> Bool? {
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []
        for pair in pairs {
            let page = pair[kIOHIDDeviceUsagePageKey] as? Int
            let usage = pair[kIOHIDDeviceUsageKey] as? Int
            if page == 0xFF43, usage == 0x0202 { return true }
            if page == 0xFF00, usage == 0x0002 { return false }
            if page == 0xFF43, usage == 0x0602 { return false }
        }
        return nil
    }

    static func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    static func bluetoothAddress(named name: String) -> String? {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }?.addressString
    }
}

struct LogitechHIDPPBatteryProvider: BatteryProvider {
    static func mxVerticalIsConnected() -> Bool {
        !LogitechInventory.shared.devices(productID: 0xB020).isEmpty
    }

    func devices() throws -> [BatteryDevice] {
        let hardware = LogitechInventory.shared.devices(productID: 0xB020)
        let candidates = hardware.filter { LogitechInventory.longOnly($0) != nil }
        if !hardware.isEmpty, candidates.isEmpty { throw BatteryProviderError.hidCollectionUnavailable }
        return try candidates.map { device in
            let session = try HIDPPSession(enumeratedDevice: device)
            defer { session.close() }
            let battery = try session.battery(device: 0xFF)
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "MX Vertical"
            let address = (IOHIDDeviceGetProperty(device, "DeviceAddress" as CFString) as? String)
                ?? LogitechInventory.bluetoothAddress(named: name)
            let hidSerial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
            let serialNumber = hidSerial ?? (try? session.serialNumber(device: 0xFF))
            return BatteryDevice(
                id: address ?? "logitech:1133:45088",
                name: name, batteryPercent: battery.percent, isConnected: true,
                source: .logitechHIDPP, isCharging: battery.charging,
                serialNumber: serialNumber, bluetoothAddress: address
            )
        }
    }
}

struct LogitechBoltBatteryProvider: BatteryProvider {
    static func boltReceiverIsConnected() -> Bool {
        !LogitechInventory.shared.devices(productID: 0xC548).isEmpty
    }

    func devices() throws -> [BatteryDevice] {
        let hardware = LogitechInventory.shared.devices(productID: 0xC548)
        let receivers = hardware.filter { LogitechInventory.longOnly($0) != nil }
        if !hardware.isEmpty, receivers.isEmpty { throw BatteryProviderError.hidCollectionUnavailable }
        return try receivers.flatMap(readPairedDevices)
    }

    private func readPairedDevices(_ receiver: IOHIDDevice) throws -> [BatteryDevice] {
        let session = try HIDPPSession(enumeratedDevice: receiver)
        defer { session.close() }
        var devices: [BatteryDevice] = []
        var failures: [String] = []
        for slot in UInt8(1)...UInt8(6) {
            let pairing: [UInt8]
            do {
                pairing = try session.register(subregister: 0x50 + slot)
            } catch BatteryProviderError.protocolError(let code) where code == 0x02 || code == 0x03 || code == 0x08 {
                // Unpaired slots return invalid-address, invalid-value or unknown-device.
                continue
            }
            guard pairing.count >= 8 else { throw BatteryProviderError.badResponse }
            guard pairing[1] & 0x40 == 0 else { continue }
            do {
                let battery = try session.battery(device: slot)
                let codename = try? session.register(subregister: 0x60 + slot, extra: 0x01)
                let name: String
                if let codename, codename.count >= 3 {
                    let end = min(3 + Int(codename[2]), codename.count)
                    name = String(bytes: codename[3..<end], encoding: .utf8) ?? "Logitech device \(slot)"
                } else {
                    name = "Logitech device \(slot)"
                }
                let unitID = pairing[4...7].map { String(format: "%02x", $0) }.joined()
                let serialNumber = try? session.serialNumber(device: slot)
                devices.append(BatteryDevice(
                    id: "bolt:\(unitID):\(slot)",
                    name: name, batteryPercent: battery.percent, isConnected: true,
                    source: .logitechHIDPP, isCharging: battery.charging,
                    serialNumber: serialNumber, bluetoothAddress: nil
                ))
            } catch {
                failures.append("slot \(slot): \(error.localizedDescription)")
            }
        }
        if devices.isEmpty, !failures.isEmpty { throw BatteryProviderError.deviceReadFailed(failures.joined(separator: "; ")) }
        return devices
    }
}

/// Owns a fresh shared-access handle, independent from discovery's IOHIDManager.
private final class HIDPPSession: @unchecked Sendable {
    private let device: IOHIDDevice
    private let longOnly: Bool
    private let queue = DispatchQueue(label: "BatteryVakt.HIDReplies")
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let lock = NSCondition()
    private var expected: [UInt8]?
    private var reply: [UInt8]?
    private var closed = false
    private let softwareID: UInt8 = 0x0E

    init(enumeratedDevice: IOHIDDevice) throws {
        guard let longOnly = LogitechInventory.longOnly(enumeratedDevice) else { throw BatteryProviderError.hidCollectionUnavailable }
        self.longOnly = longOnly
        // async-hid recreates a device from its registry entry before every open.
        let registryID = LogitechInventory.registryID(enumeratedDevice)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard service != 0 else { throw BatteryProviderError.hidUnavailable }
        defer { IOObjectRelease(service) }
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw BatteryProviderError.hidUnavailable }
        self.device = device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw BatteryProviderError.hidOpenFailed(result) }
        bufferSize = max(20, IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, Self.receive, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceActivate(device)
    }

    func close() {
        guard !closed else { return }
        closed = true
        let cancelled = DispatchSemaphore(value: 0)
        IOHIDDeviceSetCancelHandler(device) { cancelled.signal() }
        IOHIDDeviceCancel(device)
        cancelled.wait()
        IOHIDDeviceClose(device, 0)
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }

    deinit { close() }

    func register(subregister: UInt8, extra: UInt8 = 0) throws -> [UInt8] {
        // ReadLongRegister sends a short request; its reply is a long report.
        let body = try exchange([0xFF, 0x83, 0xB5, subregister, extra, 0], long: false)
        return Array(body.dropFirst(3))
    }

    private func call(device: UInt8, feature: UInt8, function: UInt8, parameters: [UInt8] = [0, 0, 0]) throws -> [UInt8] {
        let request = HIDPPWire.call(device: device, feature: feature, function: function, softwareID: softwareID, parameters: parameters)
        return Array(try exchange(request, long: longOnly).dropFirst(3))
    }

    func battery(device: UInt8) throws -> (percent: Int, charging: Bool) {
        for featureID: UInt16 in [0x1004, 0x1000] {
            let root = try call(device: device, feature: 0, function: 0, parameters: [UInt8(featureID >> 8), UInt8(featureID & 0xFF), 0])
            guard let feature = root.first, feature != 0 else { continue }
            if featureID == 0x1004 {
                let capabilities = try call(device: device, feature: feature, function: 0)
                guard capabilities.count >= 2 else { throw BatteryProviderError.badResponse }
                // Zero is not a percentage when only coarse battery levels are supported.
                if capabilities[1] & 0x02 == 0 { continue }
            }
            let payload = try call(device: device, feature: feature, function: featureID == 0x1004 ? 1 : 0)
            guard payload.count >= 3, payload[0] <= 100 else { throw BatteryProviderError.badResponse }
            return (Int(payload[0]), [1, 2, 4].contains(payload[2]))
        }
        throw BatteryProviderError.featureUnavailable
    }

    func serialNumber(device: UInt8) throws -> String {
        let root = try call(device: device, feature: 0, function: 0, parameters: [0x00, 0x03, 0])
        guard let feature = root.first, feature != 0 else { throw BatteryProviderError.featureUnavailable }
        let payload = try call(device: device, feature: feature, function: 2)
        let bytes = payload.prefix { $0 != 0 && $0 != 0xFF }
        guard bytes.count >= 4,
              bytes.allSatisfy({ (0x20...0x7E).contains($0) }),
              let serialNumber = String(bytes: bytes, encoding: .ascii) else {
            throw BatteryProviderError.badResponse
        }
        return serialNumber
    }

    private func exchange(_ request: [UInt8], long: Bool) throws -> [UInt8] {
        let report = try HIDPPWire.frame(request, long: long || longOnly)
        lock.lock()
        expected = request
        reply = nil
        lock.unlock()
        defer {
            lock.lock()
            expected = nil
            lock.unlock()
        }
        // Synchronous writes run off the serial queue that delivers replies.
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw BatteryProviderError.hidSetReportFailed(result) }
        lock.lock()
        defer { lock.unlock() }
        let deadline = Date().addingTimeInterval(1)
        while reply == nil {
            if !lock.wait(until: deadline) { break }
        }
        guard let reply else { throw BatteryProviderError.timeout }
        if reply[1] == 0x8F || reply[1] == 0xFF { throw BatteryProviderError.protocolError(reply[4]) }
        return reply
    }

    private static let receive: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
        guard result == kIOReturnSuccess, let context, reportID == 0x10 || reportID == 0x11 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        guard let body = HIDPPWire.body(of: bytes) else { return }
        let session = Unmanaged<HIDPPSession>.fromOpaque(context).takeUnretainedValue()
        session.lock.lock()
        defer { session.lock.unlock() }
        guard let expected = session.expected, HIDPPWire.matches(body, request: expected) else { return }
        session.reply = body
        session.lock.signal()
    }
}
