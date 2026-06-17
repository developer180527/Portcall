import Foundation

/// Reads per-process metadata (executable path, cumulative CPU time, resident
/// memory) for a set of PIDs via libproc — no subprocess. Returns raw samples;
/// the store derives a live CPU percent from successive samples.
struct ProcessInfoCollector: Sendable {
    func sample(pids: Set<Int32>) -> [Int32: ProcessSample] {
        var result: [Int32: ProcessSample] = [:]
        result.reserveCapacity(pids.count)
        for pid in pids {
            let task = Libproc.taskInfo(of: pid)
            result[pid] = ProcessSample(
                pid: pid,
                cpuTicks: task?.cpuTicks ?? 0,
                memoryBytes: task?.memoryBytes ?? 0,
                executablePath: Libproc.executablePath(of: pid)
            )
        }
        return result
    }
}
