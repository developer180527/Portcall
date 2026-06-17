import Foundation

/// A single raw reading for a process: cumulative CPU time plus current memory
/// and binary path. The store turns successive samples into a live CPU percent.
struct ProcessSample: Sendable {
    let pid: Int32
    /// Cumulative user+system CPU time in mach-absolute units since process
    /// start (convert with mach_timebase_info to get nanoseconds).
    let cpuTicks: UInt64
    let memoryBytes: UInt64
    let executablePath: String?
}

/// Per-process resource usage and binary location, keyed by PID and shared
/// across all sockets owned by that process.
struct ProcessStats: Sendable, Hashable {
    let pid: Int32
    /// Live percent CPU over the last scan interval (can exceed 100 on multicore).
    let cpuPercent: Double
    /// Resident set size in bytes.
    let memoryBytes: UInt64
    /// True executable image path (from libproc), independent of argv[0].
    let executablePath: String?

    /// Formatted CPU. `perCore: false` is Activity-Monitor style (100% = one
    /// core); `perCore: true` normalizes to total machine capacity.
    func cpuDisplay(perCore: Bool) -> String {
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        return String(format: "%.1f%%", perCore ? cpuPercent / cores : cpuPercent)
    }

    var memoryDisplay: String {
        guard memoryBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    /// True when we have at least one meaningful metric to show.
    var hasUsage: Bool { memoryBytes > 0 }
}
