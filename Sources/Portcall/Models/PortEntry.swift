import Foundation

/// Network transport protocol for a bound socket.
enum NetworkProtocol: String, Hashable, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// How reachable a listening socket is, derived from its bound address.
enum Exposure: Sendable {
    /// Bound to loopback only (127.0.0.0/8 or ::1). Not reachable off-host.
    case localhost
    /// Bound to a specific non-loopback interface address (e.g. a LAN IP).
    case specific
    /// Bound to all interfaces (`*`, 0.0.0.0, ::). Reachable from the network.
    case allInterfaces

    /// True when the service can be reached from outside the machine.
    var isExposed: Bool {
        switch self {
        case .localhost: return false
        case .specific, .allInterfaces: return true
        }
    }
}

/// A single listening socket owned by a process.
struct PortEntry: Identifiable, Hashable, Sendable {
    let pid: Int32
    let command: String
    let user: String
    let proto: NetworkProtocol
    /// "IPv4" or "IPv6" as reported by lsof.
    let family: String
    /// Host portion of the bound address (e.g. "127.0.0.1", "*", "::1").
    let address: String
    let port: Int

    /// Stable identity across scans so SwiftUI can diff the list smoothly.
    var id: String { "\(pid)-\(proto.rawValue)-\(family)-\(address)-\(port)" }

    var exposure: Exposure {
        switch address {
        case "*", "0.0.0.0", "::": return .allInterfaces
        case "127.0.0.1", "::1", "localhost": return .localhost
        default:
            if address.hasPrefix("127.") { return .localhost }
            return .specific
        }
    }

    /// Address shown in the UI, normalizing the wildcard for readability.
    /// lsof reports both IPv4 and IPv6 wildcards as `*`, so the family field
    /// disambiguates them (`0.0.0.0` vs `[::]`).
    var displayAddress: String {
        switch address {
        case "*", "0.0.0.0": return family == "IPv6" ? "[::]" : "0.0.0.0"
        case "::": return "[::]"
        default: return family == "IPv6" ? "[\(address)]" : address
        }
    }
}
