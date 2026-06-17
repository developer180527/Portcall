import Foundation
import Darwin

/// Thin Swift wrappers around the libproc C API. These replace the `lsof`/`ps`
/// subprocesses with direct kernel queries.
///
/// For processes owned by another user, the fd-listing calls return 0/EPERM
/// without root; those processes are skipped (same practical limitation as a
/// non-root `lsof`).
enum Libproc {
    /// All process IDs on the system.
    static func allPIDs() -> [pid_t] {
        var bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = Int(bytes) / MemoryLayout<pid_t>.stride + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return [] }
        return Array(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride))
    }

    /// The socket file descriptors open in a process.
    static func socketFDs(of pid: pid_t) -> [Int32] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let capacity = Int(bytes) / MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
        guard used > 0 else { return [] }
        let count = Int(used) / MemoryLayout<proc_fdinfo>.stride
        return fds.prefix(count).compactMap {
            $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) ? $0.proc_fd : nil
        }
    }

    /// Process accounting name (e.g. "ControlCenter", "ssh").
    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let r = proc_name(pid, &buffer, 256)
        return r > 0 ? String(cString: buffer) : "pid \(pid)"
    }

    /// Cumulative CPU time and resident memory bytes. CPU is in mach-absolute
    /// time units (NOT nanoseconds) — convert with `mach_timebase_info`.
    static func taskInfo(of pid: pid_t) -> (cpuTicks: UInt64, memoryBytes: UInt64)? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return (info.pti_total_user + info.pti_total_system, info.pti_resident_size)
    }

    /// True executable image path (robust to argv[0] rewriting, e.g. ssh).
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // 4 * MAXPATHLEN
        let r = proc_pidpath(pid, &buffer, 4096)
        return r > 0 ? String(cString: buffer) : nil
    }
}
