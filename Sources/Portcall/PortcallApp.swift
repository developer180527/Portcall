import SwiftUI
import AppKit

/// Entry point. Supports a headless `--scan` mode for debugging/verification
/// that prints the parsed entries and exits without launching the UI.
@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--scan") {
            let entries = PortScanner().scan().sorted {
                $0.port != $1.port ? $0.port < $1.port : $0.proto.rawValue < $1.proto.rawValue
            }
            // Single-shot: memory + path only. Live %CPU needs two samples and
            // is computed by the running app, not this one-off dump.
            let samples = ProcessInfoCollector().sample(pids: Set(entries.map(\.pid)))
            let containers = ContainerCollector().collect()
            for e in entries {
                let s = samples[e.pid]
                let mem = s.map { ByteCountFormatter.string(fromByteCount: Int64($0.memoryBytes), countStyle: .memory) } ?? "—"
                let path = s?.executablePath ?? "—"
                let container = containers[e.containerKey].map { " [📦 \($0.name)]" } ?? ""
                print("\(e.proto.rawValue)\t\(e.displayAddress):\(e.port)\t\(e.command) (\(e.pid))\t\(e.exposure)\t\(mem)\t\(path)\(container)")
            }
            let services = ServiceRow.grouped(from: entries)
            let exposed = services.filter { $0.exposure.isExposed }.count
            let containerized = services.filter { containers[$0.containerKey] != nil }.count
            print("— \(entries.count) sockets → \(services.count) services, \(exposed) exposed, \(containerized) in containers")
            return
        }
        PortcallApp.main()
    }
}

struct PortcallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var store: PortStore

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: PortStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .onAppear { store.start() }
        } label: {
            // Icon + live count of listening services.
            Image(systemName: store.exposedCount > 0 ? "network.badge.shield.half.filled" : "network")
            Text("\(store.listeningCount)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}

/// Hides the Dock icon so the app lives only in the menu bar, even when the
/// binary is launched directly (the bundled Info.plist also sets LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
