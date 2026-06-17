import Foundation
import Combine
import ServiceManagement

/// User-configurable settings, persisted in UserDefaults. `launchAtLogin` is not
/// stored here — it's owned by the OS via ServiceManagement and read/written live.
final class AppSettings: ObservableObject {
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }
    /// When true, CPU% is shown as a fraction of total machine capacity
    /// (÷ core count); otherwise Activity-Monitor style (100% = one core).
    @Published var cpuPerCore: Bool {
        didSet { defaults.set(cpuPerCore, forKey: Keys.cpuPerCore) }
    }
    /// Hide Apple/system daemons (by executable path) from the list.
    @Published var hideSystemServices: Bool {
        didSet { defaults.set(hideSystemServices, forKey: Keys.hideSystemServices) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let cpuPerCore = "cpuPerCore"
        static let hideSystemServices = "hideSystemServices"
    }

    init() {
        let d = UserDefaults.standard
        refreshInterval = (d.object(forKey: Keys.refreshInterval) as? Double) ?? 5
        cpuPerCore = d.bool(forKey: Keys.cpuPerCore)
        hideSystemServices = d.bool(forKey: Keys.hideSystemServices)
    }

    /// Login-item state, backed by the OS. Reads the live status; writing
    /// registers/unregisters the app as a launch-at-login item.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Portcall: launch-at-login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}
