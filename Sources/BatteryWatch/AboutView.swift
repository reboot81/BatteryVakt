import SwiftUI

struct AboutView: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                VStack(alignment: .leading) {
                    Text("BatteryVakt").font(.largeTitle.bold())
                    Text("Version \(version) (\(build))")
                        .foregroundStyle(.secondary)
                }
            }
            Text("BatteryVakt håller koll på batterinivån i anslutna HID-enheter och meddelar dig innan de tar slut. Den visar en enkel översikt i menyraden och läser Logitech MX Vertical direkt via HID++ när dess Bluetooth-gränssnitt är tillgängligt.")
            GroupBox("Integritet") {
                Text("BatteryVakt arbetar lokalt och analyserar inte innehållet i dina filer. Enhetens namn, anslutningsstatus och batterinivå används för status och lokala macOS-notiser. Direkt Logitech HID++-åtkomst aktiveras separat och används bara för batterisvar, inte tangenttryckningar. Om du själv anger ett ntfy-topic skickas varningstext, enhetsnamn, batterinivå och prioritet till ntfy; lokal IP-adress och maskinvaru-ID skickas aldrig.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Övervakade resurser") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Apple HID: batterinivåer som macOS publicerar för anslutna enheter.")
                    Text("• Logitech HID++: batterisvar från kompatibla direktanslutna enheter och Logi Bolt.")
                    ForEach(monitor.discoveredDevices) { device in
                        Text(deviceSummary(device))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Relevanta filer") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App: \(Bundle.main.bundlePath)")
                    Text("Programfil: \(Bundle.main.executablePath ?? "–")")
                    Text("Start vid inloggning: hanteras av macOS (\(monitor.settings.loginItemEnabled ? "på" : "av"))")
                    Text("Inställningar: \(preferencesPath)")
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Teknisk status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bundle-ID: \(Bundle.main.bundleIdentifier ?? "–")")
                    Text("Senaste kontroll: \(monitor.lastChecked?.formatted() ?? "–")")
                    Text("Upptäckta enheter: \(monitor.discoveredDevices.count)")
                    Text("Övervakade enheter: \(monitor.devices.count)")
                    Text("Logitech HID++: \(logitechStatus)")
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 760, height: 760)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    private var preferencesPath: String {
        let identifier = Bundle.main.bundleIdentifier ?? "com.bosaurage.BatteryVakt"
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        return library?
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(identifier).plist")
            .path ?? "–"
    }

    private var logitechStatus: String {
        guard monitor.settings.logitechHIDPPEnabled else { return "av" }
        return monitor.inputMonitoringGranted ? "på, Input Monitoring tillåten" : "på, Input Monitoring saknas"
    }

    private func deviceSummary(_ device: BatteryDevice) -> String {
        let notificationSuffix = monitor.settings.monitors(device) ? "" : ", notiser av"
        return "• \(device.name): \(device.batteryPercent) %\(notificationSuffix)"
    }
}
