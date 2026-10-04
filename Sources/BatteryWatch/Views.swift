import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        let symbol = monitor.menuBarSymbol
        let color: Color = monitor.hasAlert ? .primary : .secondary
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if monitor.settings.menuBarDisplayMode != .discreetIcon, let device = monitor.menuBarDevice {
                Text("\(device.batteryPercent)%")
                    .monospacedDigit()
            }
        }
        .foregroundStyle(color)
        .accessibilityLabel("BatteryVakt \(monitor.menuBarTitle)")
    }
}

struct StatusMenu: View {
    @ObservedObject var monitor: BatteryMonitor
    let showSettings: () -> Void
    let showAbout: () -> Void

    var body: some View {
        if monitor.devices.isEmpty {
            Text(monitor.lastError ?? "Scanning for battery devices…")
                .foregroundStyle(.secondary)
        } else {
            ForEach(monitor.devices) { device in
                Button(action: showSettings) {
                    Label(device.menuDescription, systemImage: symbol(for: device.batteryPercent))
                }
            }
        }
        Divider()
        Button("Refresh now") { monitor.refreshNow() }
        Button("Settings…", action: showSettings)
        Button("About BatteryVakt…", action: showAbout)
        Button("Quit BatteryVakt") { NSApplication.shared.terminate(nil) }
    }

    private func symbol(for percent: Int) -> String {
        if percent <= monitor.settings.criticalThreshold { return "battery.0percent" }
        if percent <= monitor.settings.lowThreshold { return "battery.25percent" }
        return "battery.100percent"
    }
}

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    let refresh: () -> Void
    let showAbout: () -> Void
    @EnvironmentObject private var monitor: BatteryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Menu bar display")
                        .font(.headline)
                    Spacer()
                    Button(action: showAbout) {
                        Label("About BatteryVakt…", systemImage: "info.circle")
                    }
                }
                HStack(spacing: 14) {
                    Picker("Menu bar display", selection: $settings.menuBarDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 360)
                    Text(settings.menuBarDisplayMode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    Button(action: refresh) { Label("Refresh now", systemImage: "arrow.clockwise") }
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LocalNotificationsCard(monitor: monitor)
            StatusCard(monitor: monitor)
            HStack(alignment: .top, spacing: 12) {
                AlertSettingsCard(settings: settings, monitor: monitor)
                    .frame(maxWidth: .infinity)
                MonitoringCard(settings: settings, monitor: monitor)
                    .frame(maxWidth: .infinity)
            }
            LogitechAccessCard(settings: settings, monitor: monitor, refresh: refresh, openInputMonitoringSettings: monitor.openInputMonitoringSettings)
            DeviceSettingsCard(settings: settings, monitor: monitor)
            NtfySettings(settings: settings, monitor: monitor)
        }
        .padding(24)
        .frame(width: 860, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $monitor.isNtfyInformationPresented) {
            NtfyInformationView(monitor: monitor)
        }
        .onAppear { Task { await monitor.refreshNotificationAuthorization() } }
        .onChange(of: settings.pollIntervalMinutes) { _, _ in monitor.restartPolling() }
        .onChange(of: settings.rotationIntervalSeconds) { _, _ in monitor.restartRotation() }
    }
}

private struct LocalNotificationsCard: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        GroupBox("Lokala notiser") {
            HStack(spacing: 12) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                if monitor.notificationAuthorizationStatus != .authorized,
                   monitor.notificationAuthorizationStatus != .provisional {
                    Button("Öppna notisinställningar", action: monitor.openNotificationSettings)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusTitle: String {
        switch monitor.notificationAuthorizationStatus {
        case .authorized, .provisional: "Lokala notiser är på"
        case .denied, .notDetermined: "Av – BatteryVakt kan inte visa lokala notiser"
        @unknown default: "Status för lokala notiser är okänd"
        }
    }

    private var statusSymbol: String {
        switch monitor.notificationAuthorizationStatus {
        case .authorized, .provisional: "checkmark.circle.fill"
        case .denied, .notDetermined: "exclamationmark.triangle.fill"
        @unknown default: "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch monitor.notificationAuthorizationStatus {
        case .authorized, .provisional: .green
        case .denied, .notDetermined: .orange
        @unknown default: .secondary
        }
    }
}

private struct StatusCard: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        GroupBox("Status") {
            HStack(spacing: 12) {
                Image(systemName: monitor.devices.isEmpty ? "battery.100percent" : monitor.menuBarSymbol)
                    .font(.title2)
                    .foregroundStyle(monitor.hasAlert ? .primary : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.lastError ?? "BatteryVakt is monitoring connected devices")
                        .font(.headline)
                    Text("Last check: \(monitor.lastChecked?.formatted(date: .abbreviated, time: .shortened) ?? "–")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AlertSettingsCard: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        GroupBox("Battery alerts") {
            VStack(spacing: 6) {
                PercentageRow(title: "Low", value: $settings.lowThreshold) {
                    monitor.testBatteryAlert(severity: .low)
                }
                PercentageRow(title: "Critical", value: $settings.criticalThreshold) {
                    monitor.testBatteryAlert(severity: .critical)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PercentageRow: View {
    let title: String
    @Binding var value: Int
    let test: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            Text("%")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            TestPlaneButton(title: "Test \(title.lowercased()) battery alert", action: test)
        }
    }
}

private struct MonitoringCard: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        GroupBox("Monitoring") {
            VStack(spacing: 6) {
                HStack {
                    Text("Check interval")
                    Spacer()
                    TextField("Minutes", value: $settings.pollIntervalMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("minutes").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Launch BatteryVakt at login")
                    Spacer()
                    Toggle("", isOn: $settings.loginItemEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .frame(width: 44, alignment: .center)
                }
                HStack {
                    Text("Switch menu-bar device every")
                    Spacer()
                    TextField("Seconds", value: $settings.rotationIntervalSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("seconds").foregroundStyle(.secondary)
                }
                .opacity(settings.menuBarDisplayMode == .rotateDevices ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LogitechAccessCard: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var monitor: BatteryMonitor
    let refresh: () -> Void
    let openInputMonitoringSettings: () -> Void

    var body: some View {
        GroupBox("Logitech HID++") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: accessStatusSymbol)
                        .foregroundStyle(accessStatusColor)
                    Text("Logitech HID++ battery access")
                        .font(.headline)
                    Spacer()
                    Button {
                        monitor.isLogitechAccessInformationPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Why Input Monitoring is needed")
                    .popover(isPresented: $monitor.isLogitechAccessInformationPresented, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("macOS requires Input Monitoring permission for raw Logitech HID++ reports. BatteryVakt uses that access only for battery replies; it does not read, retain or react to keystrokes. You can keep this off and still monitor standard Apple HID battery devices.")
                                .fixedSize(horizontal: false, vertical: true)
                            if settings.logitechHIDPPEnabled {
                                Divider()
                                Text("Logitech debug information")
                                    .font(.headline)
                                Text(detectedHardwareText)
                                Text(logitechDebugText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(width: 380, alignment: .leading)
                        .padding(18)
                    }
                    Toggle("", isOn: $settings.logitechHIDPPEnabled)
                        .labelsHidden()
                        .onChange(of: settings.logitechHIDPPEnabled) { _, enabled in
                            if enabled {
                                if !monitor.inputMonitoringGranted {
                                    openInputMonitoringSettings()
                                }
                                refresh()
                            }
                        }
                }
                if settings.logitechHIDPPEnabled {
                    HStack(spacing: 10) {
                        Button("Check Logitech device now", action: refresh)
                        if !monitor.inputMonitoringGranted {
                            Button("Open Input Monitoring Settings", action: openInputMonitoringSettings)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var detectedHardwareText: String {
        switch (monitor.mxVerticalDetected, monitor.boltReceiverDetected) {
        case (true, true):
            return "Detected: MX Vertical and a Logi Bolt receiver."
        case (true, false):
            return "Detected: MX Vertical."
        case (false, true):
            return "Detected: Logi Bolt receiver."
        case (false, false):
            return "For a compatible Logitech device, when one is connected."
        }
    }

    private var logitechDebugText: String {
        if !monitor.boltStatus.isEmpty { return monitor.boltStatus }
        if monitor.inputMonitoringGranted {
            return "Input Monitoring is allowed. HID++ battery reading succeeded."
        }
        return "Input Monitoring is not allowed."
    }

    private var accessStatusSymbol: String {
        if !settings.logitechHIDPPEnabled { return "circle" }
        return monitor.inputMonitoringGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var accessStatusColor: Color {
        if !settings.logitechHIDPPEnabled { return .secondary }
        return monitor.inputMonitoringGranted ? .green : .orange
    }
}

private struct DeviceSettingsCard: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        GroupBox("Devices") {
            if monitor.discoveredDevices.isEmpty {
                Text("No battery devices have been found yet.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Text("Included")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(monitor.discoveredDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(device.name)
                                    if let details = device.identityDetails {
                                        Text(details)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                Text("\(device.batteryPercent)% · \(device.source.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Monitor", isOn: Binding(
                                get: { settings.monitors(device) },
                                set: { monitor.setMonitoring(device, enabled: $0) }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        }
    }
}

private struct NtfySettings: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var monitor: BatteryMonitor

    private var validation: NtfyTopicValidation { NtfyTopicValidator.validate(settings.ntfyTopic) }

    var body: some View {
        GroupBox("ntfy") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Topic") {
                    HStack(spacing: 8) {
                        TextField("batteryvakt-a7f24c91e30b", text: $settings.ntfyTopic)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 440)
                        Button { settings.ntfyTopic = NtfyTopicGenerator.makeTopic() } label: {
                            Image(systemName: "dice")
                        }
                        .buttonStyle(.bordered)
                        .help("Skapa säkert topic")
                        Button {
                            Task {
                                try? await monitor.testNtfy()
                            }
                        } label: {
                            Label("Testa notis", systemImage: "paperplane")
                        }
                        .disabled(validation != .valid)
                        Button("Vad är ntfy?") { monitor.showNtfyInformation() }
                    }
                }
                if let message = validationMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Enhetsnamn") {
                    TextField(Host.current().localizedName ?? "Mac", text: $settings.remoteDeviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 440)
                }
                Text("Skickar varningar för låg eller kritisk batterinivå. Topic fungerar som ett lösenord; välj ett långt, svårgissat namn. Lämna tomt för att stänga av ntfy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !monitor.ntfyTestStatus.isEmpty { Text(monitor.ntfyTestStatus).font(.caption) }
            }
        }
        .onChange(of: settings.ntfyTopic) { _, _ in monitor.clearNtfyTestStatus() }
    }

    private var validationMessage: String? {
        switch validation {
        case .empty, .valid: nil
        case .tooLong: "Topic may contain at most 64 characters."
        case .invalidCharacters: "Use only A–Z, a–z, 0–9, hyphen and underscore."
        }
    }
}

private struct NtfyInformationView: View {
    @ObservedObject var monitor: BatteryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.mint)
            Text("Vad är ntfy?")
                .font(.title.bold())
            Text("ntfy är en frivillig extern tjänst som skickar BatteryVakts viktiga batterivarningar till exempelvis din mobil. Installera ntfy-appen och prenumerera på exakt samma topic som du skriver här. Topic fungerar som en hemlig kanalnyckel, så välj ett långt och svårgissat namn. BatteryVakt skapar inget konto och ntfy behövs inte för lokala notiser.")
                .font(.title3.weight(.medium))
            Spacer()
            Link("Öppna ntfy-guiden", destination: URL(string: "https://docs.ntfy.sh/")!)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            Button("Stäng") { monitor.hideNtfyInformation() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(width: 500, height: 610)
    }
}

private struct TestPlaneButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "paperplane") }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(title)
            .accessibilityLabel(title)
    }
}
