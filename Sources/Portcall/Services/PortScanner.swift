import Foundation

/// Collects listening TCP/UDP sockets by invoking `lsof` in field-output mode
/// and normalizing the result into `PortEntry` values.
///
/// Phase 1 shells out to `/usr/sbin/lsof`. A later phase will replace this with
/// `libproc`/`proc_pidinfo` for lower overhead and to drop the external process.
struct PortScanner: Sendable {
    private let lsofPath = "/usr/sbin/lsof"

    /// Run a full scan: TCP listeners + bound (unconnected) UDP sockets.
    func scan() -> [PortEntry] {
        var entries: [PortEntry] = []
        // -n: no DNS, -P: no port-name lookup -> fast and stable to parse.
        entries += parse(Shell.run(lsofPath, ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLPtnT"]),
                         defaultProtocol: .tcp)
        entries += parse(Shell.run(lsofPath, ["-nP", "-iUDP", "-FpcLPtnT"]),
                         defaultProtocol: .udp)
        return entries
    }

    // MARK: - Field-output parsing

    /// Parse lsof `-F` output. Process-level fields (`p`,`c`,`L`) appear once,
    /// then file-level fields (`f`,`t`,`P`,`n`,`T`) repeat per open socket.
    private func parse(_ output: String, defaultProtocol: NetworkProtocol) -> [PortEntry] {
        var results: [PortEntry] = []

        var pid: Int32 = 0
        var command = ""
        var user = ""

        var family = ""
        var proto: NetworkProtocol?
        var name = ""
        var isListening = false
        var inFile = false

        func flush() {
            defer {
                inFile = false
                family = ""; proto = nil; name = ""; isListening = false
            }
            guard inFile, !name.isEmpty else { return }
            // Skip connected sockets (e.g. active UDP flows "src->dst").
            guard !name.contains("->") else { return }
            guard let (address, port) = splitHostPort(name) else { return }
            // TCP rows are already filtered to LISTEN by lsof; UDP has no state.
            if defaultProtocol == .tcp && !isListening { return }
            results.append(
                PortEntry(
                    pid: pid,
                    command: command,
                    user: user,
                    proto: proto ?? defaultProtocol,
                    family: family.isEmpty ? "IPv4" : family,
                    address: address,
                    port: port
                )
            )
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int32(value) ?? 0
            case "c":
                command = value
            case "L":
                user = value
            case "f":
                flush()
                inFile = true
            case "t":
                family = value
            case "P":
                proto = NetworkProtocol(rawValue: value)
            case "n":
                name = value
            case "T":
                if value.hasPrefix("ST=") {
                    isListening = value.dropFirst(3) == "LISTEN"
                }
            default:
                break
            }
        }
        flush()
        return results
    }

    /// Split an lsof address into (host, port). Handles `*:53`, `127.0.0.1:8080`,
    /// `[::1]:8080`, and bracketless IPv6 like `fe80::1:53`.
    private func splitHostPort(_ name: String) -> (String, Int)? {
        if name.hasPrefix("["), let close = name.firstIndex(of: "]") {
            let host = String(name[name.index(after: name.startIndex)..<close])
            let rest = name[name.index(after: close)...] // ":port"
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return nil }
            return (host, port)
        }
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let host = String(name[..<colon])
        guard let port = Int(name[name.index(after: colon)...]) else { return nil }
        return (host.isEmpty ? "*" : host, port)
    }
}
