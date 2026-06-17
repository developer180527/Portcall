import SwiftUI

/// The "Portcall Settings" window (a standard macOS Settings scene).
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
            } footer: {
                Text("Registers Portcall with macOS to start automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scanning") {
                Picker("Refresh interval", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
            }

            Section("Display") {
                Picker("CPU usage", selection: $settings.cpuPerCore) {
                    Text("Activity Monitor (100% = one core)").tag(false)
                    Text("Percent of all cores").tag(true)
                }
                Toggle("Hide system services", isOn: $settings.hideSystemServices)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.launchAtLogin },
                set: { settings.launchAtLogin = $0 })
    }
}
