import Foundation
import Darwin

/// Gathers per-process metadata (executable path, CPU, memory) for a set of PIDs.
///
/// The executable path comes from `proc_pidpath` (libproc) because it returns
/// the real image path even when a process rewrites its argv[0] / process title
/// (e.g. `ssh`, which reports a fake title to `ps`). CPU% and resident memory
/// come from a single batched `ps` invocation.
struct ProcessInfoCollector: Sendable {
    func collect(pids: Set<Int32>) -> [Int32: ProcessStats] {
        guard !pids.isEmpty else { return [:] }
        let usage = resourceUsage(for: pids)
        var result: [Int32: ProcessStats] = [:]
        result.reserveCapacity(pids.count)
        for pid in pids {
            let u = usage[pid]
            result[pid] = ProcessStats(
                pid: pid,
                cpuPercent: u?.cpu ?? 0,
                memoryBytes: u?.rss ?? 0,
                executablePath: Self.executablePath(for: pid)
            )
        }
        return result
    }

    /// Resolve a PID's executable image path via libproc.
    static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // 4 * MAXPATHLEN
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// One `ps` call yielding (%CPU, RSS-bytes) for every requested PID.
    private func resourceUsage(for pids: Set<Int32>) -> [Int32: (cpu: Double, rss: UInt64)] {
        let list = pids.map(String.init).joined(separator: ",")
        let output = Shell.run("/bin/ps", ["-o", "pid=,%cpu=,rss=", "-p", list])

        var map: [Int32: (cpu: Double, rss: UInt64)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]) else { continue }
            map[pid] = (cpu, rssKB * 1024)
        }
        return map
    }
}
