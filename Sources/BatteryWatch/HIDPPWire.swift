import Foundation

/// HID++ framing shared by the native transport and byte-level regression tests.
enum HIDPPWire {
    static func frame(_ body: [UInt8], long: Bool) throws -> [UInt8] {
        let capacity = long ? 19 : 6
        guard body.count >= 3, body.count <= capacity else { throw BatteryProviderError.badResponse }
        return [long ? 0x11 : 0x10] + body + Array(repeating: 0, count: capacity - body.count)
    }

    /// IOKit includes the numbered report ID in the callback buffer already.
    static func body(of report: [UInt8]) -> [UInt8]? {
        guard let id = report.first, (id == 0x10 && report.count == 7) || (id == 0x11 && report.count == 20) else { return nil }
        return Array(report.dropFirst())
    }

    static func matches(_ body: [UInt8], request: [UInt8]) -> Bool {
        guard body.count >= 6, request.count >= 3, body[0] == request[0] else { return false }
        if body[1] == 0x8F || body[1] == 0xFF {
            return body[2] == request[1] && body[3] == request[2]
        }
        guard body[1] == request[1], body[2] == request[2] else { return false }
        return request[1] != 0x83 || request[2] != 0xB5 || (request.count >= 4 && body[3] == request[3])
    }

    static func call(device: UInt8, feature: UInt8, function: UInt8, softwareID: UInt8, parameters: [UInt8]) -> [UInt8] {
        [device, feature, (function << 4) | (softwareID & 0x0F)] + parameters
    }
}
