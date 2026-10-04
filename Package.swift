// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryWatch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BatteryWatch", targets: ["BatteryWatch"])],
    targets: [.executableTarget(name: "BatteryWatch")]
)
