import Foundation
import Combine
import Darwin

/// Central, observable state for the UI. Owns the scan timer and exposes the
/// current set of listening sockets plus derived/filtered views of them.
@MainActor
final class PortStore: ObservableObject {
    /// All grouped services from the last scan, before the system-service filter.
    @Published private(set) var allServices: [ServiceRow] = []
    @Published private(set) var processStats: [Int32: ProcessStats] = [:]
    @Published private(set) var containers: [String: ContainerInfo] = [:]
    @Published private(set) var lastScan: Date?
    @Published private(set) var isScanning = false
    @Published var searchText = ""

    let settings: AppSettings

    private let scanner = PortScanner()
    private let collector = ProcessInfoCollector()
    private let containerCollector = ContainerCollector()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Containers churn far slower than ports, and `docker ps` forks a
    /// subprocess (~15ms) — by far the heaviest part of a scan. So poll it on
    /// its own slower cadence and reuse the cached map on intervening scans.
    private let containerInterval: TimeInterval = 20
    private var lastContainerPoll: Date?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Visible services, applying the "hide system services" setting.
    var services: [ServiceRow] {
        guard settings.hideSystemServices else { return allServices }
        return allServices.filter { !isSystemService($0) }
    }

    /// Heuristic: Apple/system daemons live under these prefixes. Deliberately
    /// excludes /usr/bin and /opt/homebrew so user tools (and the ssh-forwarded
    /// container ports) stay visible.
    private func isSystemService(_ service: ServiceRow) -> Bool {
        guard let path = processStats[service.pid]?.executablePath else { return false }
        return path.hasPrefix("/System/")
            || path.hasPrefix("/usr/libexec/")
            || path.hasPrefix("/Library/Apple/")
    }

    /// Previous CPU sample per PID (mach ticks) + when it was taken, for live
    /// %CPU deltas, plus the mach→nanosecond timebase.
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousSampleTime: DispatchTime?
    private let cpuTimebase: (numer: Double, denom: Double) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (Double(tb.numer), Double(tb.denom))
    }()

    /// Number of distinct listening services, shown in the menu bar.
    var listeningCount: Int { services.count }

    /// Listening services reachable from outside this machine.
    var exposedCount: Int { services.filter { $0.exposure.isExposed }.count }

    /// Number of listening services attributable to a running container.
    var containerizedCount: Int { services.filter { containers[$0.containerKey] != nil }.count }

    func container(for service: ServiceRow) -> ContainerInfo? { containers[service.containerKey] }

    /// Search-filtered services for the list. Matches process, address, port,
    /// PID, protocol, and container name/image.
    var filteredServices: [ServiceRow] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return services }
        return services.filter { service in
            let container = containers[service.containerKey]
            return service.command.lowercased().contains(query)
                || service.displayAddress.lowercased().contains(query)
                || String(service.port).contains(query)
                || String(service.pid).contains(query)
                || service.proto.rawValue.lowercased().contains(query)
                || (container?.name.lowercased().contains(query) ?? false)
                || (container?.image.lowercased().contains(query) ?? false)
        }
    }

    /// Begin scanning immediately and on a repeating timer. Re-renders and
    /// reschedules when settings change (e.g. a new refresh interval).
    func start() {
        Task { await refresh() }
        scheduleTimer()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
                self?.scheduleTimer()
            }
            .store(in: &cancellables)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Run one scan off the main actor and publish the sorted result, enriched
    /// with per-process stats gathered in the same background pass. Containers
    /// are polled on their own slower cadence unless `forceContainers` is set
    /// (e.g. a manual refresh).
    func refresh(forceContainers: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        let scanner = self.scanner
        let collector = self.collector
        let containerCollector = self.containerCollector
        let pollContainers = forceContainers || shouldPollContainers()

        // `containers` is nil when we skip the docker poll this tick.
        let (scanned, samples, containers, sampledAt) = await Task.detached(priority: .utility) {
            let sockets = scanner.scan()
            let samples = collector.sample(pids: Set(sockets.map(\.pid)))
            let containers = pollContainers ? containerCollector.collect() : nil
            return (sockets, samples, containers, DispatchTime.now())
        }.value

        let sorted = scanned.sorted {
            $0.port != $1.port ? $0.port < $1.port : $0.proto.rawValue < $1.proto.rawValue
        }
        allServices = ServiceRow.grouped(from: sorted)
        processStats = computeStats(from: samples, at: sampledAt)
        if let containers {
            self.containers = containers
            lastContainerPoll = Date()
        }
        lastScan = Date()
        isScanning = false
    }

    /// Whether enough time has elapsed to re-run `docker ps`.
    private func shouldPollContainers() -> Bool {
        guard let last = lastContainerPoll else { return true } // first scan
        return Date().timeIntervalSince(last) >= containerInterval
    }

    /// Turn raw samples into display stats, deriving live %CPU from the change in
    /// cumulative CPU time over wall-clock elapsed since the previous scan.
    private func computeStats(from samples: [Int32: ProcessSample],
                              at sampledAt: DispatchTime) -> [Int32: ProcessStats] {
        let elapsedNanos = previousSampleTime.map {
            Double(sampledAt.uptimeNanoseconds - $0.uptimeNanoseconds)
        }
        var stats: [Int32: ProcessStats] = [:]
        stats.reserveCapacity(samples.count)
        for (pid, sample) in samples {
            var cpu = 0.0
            if let elapsedNanos, elapsedNanos > 0,
               let previous = previousCPU[pid], sample.cpuTicks >= previous {
                // Convert the CPU-time delta from mach ticks to nanoseconds,
                // then express it as a fraction of wall-clock elapsed.
                let cpuNanos = Double(sample.cpuTicks - previous) * cpuTimebase.numer / cpuTimebase.denom
                cpu = cpuNanos / elapsedNanos * 100.0
            }
            stats[pid] = ProcessStats(
                pid: pid,
                cpuPercent: cpu,
                memoryBytes: sample.memoryBytes,
                executablePath: sample.executablePath
            )
        }
        previousCPU = samples.mapValues(\.cpuTicks)
        previousSampleTime = sampledAt
        return stats
    }
}
