import Foundation

@main
struct HIDPPWireTests {
    static func main() throws {
        let root = HIDPPWire.call(device: 0xFF, feature: 0, function: 0, softwareID: 0x0E, parameters: [0x10, 0, 0])
        let bluetooth = try HIDPPWire.frame(root, long: true)
        precondition(bluetooth.count == 20 && bluetooth.prefix(7) == [0x11, 0xFF, 0, 0x0E, 0x10, 0, 0])
        let battery = HIDPPWire.call(device: 1, feature: 8, function: 1, softwareID: 0x0E, parameters: [0, 0, 0])
        precondition(battery[2] == 0x1E, "Function ID must occupy the high nibble")
        let input: [UInt8] = [0x11, 1, 8, 0x1E, 76, 4, 0] + Array(repeating: 0, count: 13)
        let decoded = HIDPPWire.body(of: input)!
        precondition(decoded[3] == 76, "Report ID must be removed exactly once")
        precondition(HIDPPWire.matches(decoded, request: battery))
        var notification = decoded
        notification[2] = 0x10
        precondition(!HIDPPWire.matches(notification, request: battery))
        var otherDevice = decoded
        otherDevice[0] = 2
        precondition(!HIDPPWire.matches(otherDevice, request: battery))
        let receiver: [UInt8] = [0xFF, 0x83, 0xB5, 0x51, 0, 0]
        let receiverFrame = try HIDPPWire.frame(receiver, long: false)
        precondition(receiverFrame == [0x10, 0xFF, 0x83, 0xB5, 0x51, 0, 0])
        let longReply: [UInt8] = [0x11, 0xFF, 0x83, 0xB5, 0x51, 2, 0x12, 0x34] + Array(repeating: 0, count: 12)
        precondition(HIDPPWire.matches(HIDPPWire.body(of: longReply)!, request: receiver))
        let receiverError: [UInt8] = [0xFF, 0x8F, 0x83, 0xB5, 0x02, 0]
        precondition(HIDPPWire.matches(receiverError, request: receiver))
        let featureError: [UInt8] = [1, 0xFF, 8, 0x1E, 0x09, 0]
        precondition(HIDPPWire.matches(featureError, request: battery))
        precondition(HIDPPWire.body(of: [0x11, 1, 8]) == nil)
        let wrongSlot: [UInt8] = [0xFF, 0x83, 0xB5, 0x52, 0, 0]
        precondition(!HIDPPWire.matches(wrongSlot, request: receiver))
        let identified = BatteryDevice(
            id: "test", name: "Mouse", batteryPercent: 50, isConnected: true,
            source: .appleHID, isCharging: false, serialNumber: "ABC123",
            bluetoothAddress: "aa-bb-cc-dd-ee-ff"
        )
        precondition(identified.identityDetails == "SN: ABC123 · MAC: AA:BB:CC:DD:EE:FF")
        print("HID++ regression checks passed: BLE framing, function nibble, reply offsets, reply matching, receiver framing, error replies.")
    }
}
