import Foundation

/// Correlates listening host ports with running containers. Works with any
/// runtime that ships the `docker` CLI (Docker Desktop, Colima, OrbStack,
/// Rancher Desktop).
///
/// Entirely optional: if no runtime is installed or the daemon is unreachable,
/// `collect()` returns an empty map and the rest of the app is unaffected.
///
/// Correlation is by host **port**, not PID — Colima forwards container ports
/// through a host-side `ssh` process, so the socket's owning process is never
/// the container itself. Matching on the published host port handles that
/// (and the direct Docker Desktop case) uniformly.
struct ContainerCollector: Sendable {
    /// GUI apps launched from Finder inherit a minimal PATH that excludes
    /// Homebrew, so probe absolute locations instead of relying on PATH.
    private static let dockerCandidates = [
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker",
        "/usr/bin/docker",
    ]

    /// Map of `"proto:hostPort"` (e.g. `"tcp:6881"`) to the owning container.
    func collect() -> [String: ContainerInfo] {
        guard let docker = Self.dockerPath() else { return [:] }
        // 2s timeout so a stopped/unreachable daemon can't stall the scan.
        let output = Shell.run(
            docker,
            ["ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}"],
            timeout: 2
        )
        guard !output.isEmpty else { return [:] }

        var map: [String: ContainerInfo] = [:]
        for line in output.split(separator: "\n") {
            let columns = String(line).components(separatedBy: "\t")
            guard columns.count == 4 else { continue }
            let info = ContainerInfo(
                id: String(columns[0].prefix(12)),
                name: columns[1],
                image: columns[2]
            )
            for key in Self.hostPortKeys(from: columns[3]) {
                map[key] = info
            }
        }
        return map
    }

    static func dockerPath() -> String? {
        dockerCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Parse a `docker ps` Ports field into `["proto:hostPort", ...]`, skipping
    /// segments not published to the host (those have no `->`).
    /// Example input: `0.0.0.0:6881->6881/tcp, [::]:6881->6881/tcp, 127.0.0.1:8080->8080/tcp`
    static func hostPortKeys(from portsField: String) -> [String] {
        var keys: [String] = []
        for segment in portsField.components(separatedBy: ", ") {
            let halves = segment.components(separatedBy: "->")
            guard halves.count == 2 else { continue }
            let hostSide = halves[0]          // "0.0.0.0:6881" / "[::]:6881" / "127.0.0.1:8080"
            let containerSide = halves[1]     // "6881/tcp"
            guard let colon = hostSide.lastIndex(of: ":"),
                  let hostPort = Int(hostSide[hostSide.index(after: colon)...]) else { continue }
            let proto = containerSide.components(separatedBy: "/").last?.lowercased() ?? "tcp"
            keys.append("\(proto):\(hostPort)")
        }
        return keys
    }
}
