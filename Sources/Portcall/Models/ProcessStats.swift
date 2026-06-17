import Foundation

/// Per-process resource usage and binary location, keyed by PID and shared
/// across all sockets owned by that process.
struct ProcessStats: Sendable, Hashable {
    let pid: Int32
    /// Percent CPU as reported by `ps` (can exceed 100 on multicore).
    let cpuPercent: Double
    /// Resident set size in bytes.
    let memoryBytes: UInt64
    /// True executable image path (from libproc), independent of argv[0].
    let executablePath: String?

    var cpuDisplay: String { String(format: "%.1f%%", cpuPercent) }

    var memoryDisplay: String {
        guard memoryBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    /// True when we have at least one meaningful metric to show.
    var hasUsage: Bool { memoryBytes > 0 }
}
