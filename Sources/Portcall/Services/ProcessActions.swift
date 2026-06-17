import AppKit
import Darwin

/// Side-effecting quick actions invoked from the UI. Kept separate from views
/// so the behavior is testable and reused across rows.
enum ProcessActions {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    static func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Send SIGTERM to a process (graceful termination).
    static func terminate(pid: Int32) {
        kill(pid, SIGTERM)
    }

    /// Build an http(s) URL for a TCP service, or nil for UDP. Wildcard/localhost
    /// binds open against `localhost`; a specific bind opens against that address
    /// (the display address is already bracketed for IPv6).
    static func webURL(for service: ServiceRow) -> URL? {
        guard service.proto == .tcp else { return nil }
        let host: String
        switch service.exposure {
        case .localhost, .allInterfaces:
            host = "localhost"
        case .specific:
            host = service.displayAddresses.first ?? "localhost"
        }
        let scheme = [443, 8443, 4443].contains(service.port) ? "https" : "http"
        return URL(string: "\(scheme)://\(host):\(service.port)")
    }

    static func openWeb(for service: ServiceRow) {
        guard let url = webURL(for: service) else { return }
        NSWorkspace.shared.open(url)
    }
}
