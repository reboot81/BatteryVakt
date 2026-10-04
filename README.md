# BatteryVakt

A small native macOS menu-bar monitor for Bluetooth/HID battery devices.

## Run

Open `BatteryWatch.xcodeproj` in Xcode and run the `BatteryVakt` scheme. The app
must be built as an application bundle, not as a Swift Package executable, for
notifications and login-item support.

`scripts/build-local.sh` is a maintainer-only packaging helper. It deliberately
expects the ignored `work/signing` identity and a local `rcodesign` binary; neither
private signing material nor built apps are committed. Replacing a signing
identity changes the app identity macOS uses for privacy permissions.

Development builds are not notarized distributions for other Macs. A default
ad-hoc Xcode build may require a new Input Monitoring approval after recompilation.

The app has no runtime dependencies. It reads Apple-compatible HID battery properties through `IOHIDManager` and has a focused HID++ 2.0 implementation for a directly connected Logitech MX Vertical (`046d:b020`). The Logitech provider resolves the legacy `0x1000` BatteryStatus feature through Root (`0x0000`) on every poll; it does not assume a fixed feature index.

macOS may require the application to be signed and granted the relevant HID/Input Monitoring permission before a device exposes its vendor HID++ interface. The app leaves ordinary mouse input untouched.

## HID++ implementation reference

The transport was checked against OpenLogi commit
`4863a45e256d80404b95232b513793cbccb5d6d6` and its async-hid fork commit
`1659d8e2eec4f6ea0af4324ee70ff07db06f8839`:

- [Native transport and usage-pair selection](https://github.com/AprilNEA/OpenLogi/blob/4863a45e256d80404b95232b513793cbccb5d6d6/crates/openlogi-hid/src/transport/native.rs)
- [Fresh shared IOHID handles and callbacks](https://github.com/AprilNEA/async-hid/tree/1659d8e2eec4f6ea0af4324ee70ff07db06f8839/src/backend/iohidmanager)
- [Bolt receiver registers](https://github.com/AprilNEA/OpenLogi/blob/4863a45e256d80404b95232b513793cbccb5d6d6/crates/openlogi-hidpp/src/receiver/bolt.rs)

Bluetooth FF43:0202 uses 20-byte reports; Bolt FF00:0002 accepts short requests.
Discovery examines every usage pair, and each session recreates a fresh handle
from the registry entry before opening with option 0 (shared, not exclusive).
Replies retain their report ID exactly once. Feature functions occupy the high
nibble, and replies must match device, feature, function and software ID.

Battery features 0x1004 and 0x1000 are resolved through Root dynamically. Devices
that only advertise coarse levels are not presented as a fabricated 0% reading.
Current supported transports are direct MX Vertical b020 and Bolt c548; this is
not a complete implementation of all Logitech receivers or features.

`Tests/HIDPPWireTests.swift` covers framing, reply offsets, matching and errors.
Real battery reads require Input Monitoring permission inside the app; CLI probes
do not inherit that permission. Direct MX Vertical and Logi Bolt battery reading
have been verified on macOS hardware.
