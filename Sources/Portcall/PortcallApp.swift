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
            let stats = ProcessInfoCollector().collect(pids: Set(entries.map(\.pid)))
            for e in entries {
                let s = stats[e.pid]
                let cpu = s.map { String(format: "%.1f%%", $0.cpuPercent) } ?? "—"
                let mem = s?.memoryDisplay ?? "—"
                let path = s?.executablePath ?? "—"
                print("\(e.proto.rawValue)\t\(e.displayAddress):\(e.port)\t\(e.command) (\(e.pid))\t\(e.exposure)\tCPU \(cpu)\t\(mem)\t\(path)")
            }
            print("— \(entries.count) listening, \(entries.filter { $0.exposure.isExposed }.count) exposed")
            return
        }
        PortcallApp.main()
    }
}

struct PortcallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PortStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(store)
                .onAppear { store.start() }
        } label: {
            // Icon + live count of listening services.
            Image(systemName: store.exposedCount > 0 ? "network.badge.shield.half.filled" : "network")
            Text("\(store.listeningCount)")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon so the app lives only in the menu bar, even when the
/// binary is launched directly (the bundled Info.plist also sets LSUIElement).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
