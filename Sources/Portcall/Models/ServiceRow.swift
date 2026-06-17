import Foundation

/// A logical listening service for display: one or more raw sockets from the
/// same process on the same protocol + port + exposure, collapsed across
/// address families (IPv4/IPv6). A dual-stack bind shows as a single row.
///
/// Grouping by *exposure* (not just port) keeps a localhost bind and a wildcard
/// bind on the same port as separate rows, since their reachability differs.
struct ServiceRow: Identifiable, Hashable {
    let pid: Int32
    let command: String
    let proto: NetworkProtocol
    let port: Int
    let exposure: Exposure
    /// Address families represented, e.g. ["IPv4", "IPv6"].
    let families: [String]
    /// Normalized bound addresses, IPv4 first, e.g. ["0.0.0.0", "[::]"].
    let displayAddresses: [String]

    var id: String {
        "\(pid)-\(proto.rawValue)-\(port)-\(displayAddresses.joined(separator: ","))"
    }

    /// Container lookup key (matches ContainerCollector / PortEntry).
    var containerKey: String { "\(proto.rawValue.lowercased()):\(port)" }

    /// Combined address for display, e.g. "0.0.0.0 · [::]".
    var displayAddress: String { displayAddresses.joined(separator: " · ") }

    /// Single usable address for copy/open actions (IPv4 form when present).
    var primaryAddress: String { displayAddresses.first ?? displayAddress }

    var isDualStack: Bool { families.count > 1 }

    /// Collapse raw sockets into services, preserving input (port) ordering.
    static func grouped(from entries: [PortEntry]) -> [ServiceRow] {
        struct Key: Hashable {
            let pid: Int32
            let proto: NetworkProtocol
            let port: Int
            let exposure: Exposure
        }

        var buckets: [Key: [PortEntry]] = [:]
        var order: [Key] = []
        for entry in entries {
            let key = Key(pid: entry.pid, proto: entry.proto, port: entry.port, exposure: entry.exposure)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }

        return order.map { key in
            let group = buckets[key]!.sorted { familyRank($0.family) < familyRank($1.family) }
            var addresses: [String] = []
            var families: [String] = []
            for entry in group {
                if !addresses.contains(entry.displayAddress) { addresses.append(entry.displayAddress) }
                if !families.contains(entry.family) { families.append(entry.family) }
            }
            let first = group[0]
            return ServiceRow(
                pid: key.pid,
                command: first.command,
                proto: key.proto,
                port: key.port,
                exposure: key.exposure,
                families: families,
                displayAddresses: addresses
            )
        }
    }

    private static func familyRank(_ family: String) -> Int {
        switch family {
        case "IPv4": return 0
        case "IPv6": return 1
        default: return 2
        }
    }
}
