import Foundation
import Combine

/// Central, observable state for the UI. Owns the scan timer and exposes the
/// current set of listening sockets plus derived/filtered views of them.
@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var entries: [PortEntry] = []
    @Published private(set) var processStats: [Int32: ProcessStats] = [:]
    @Published private(set) var lastScan: Date?
    @Published private(set) var isScanning = false
    @Published var searchText = ""

    /// Seconds between automatic scans.
    let refreshInterval: TimeInterval = 5

    private let scanner = PortScanner()
    private let collector = ProcessInfoCollector()
    private var timer: Timer?

    /// Number of distinct listening services, shown in the menu bar.
    var listeningCount: Int { entries.count }

    /// Listening services reachable from outside this machine.
    var exposedCount: Int { entries.filter { $0.exposure.isExposed }.count }

    /// Search-filtered, port-sorted entries for the list.
    var filteredEntries: [PortEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.command.lowercased().contains(query)
                || entry.displayAddress.lowercased().contains(query)
                || String(entry.port).contains(query)
                || String(entry.pid).contains(query)
                || entry.proto.rawValue.lowercased().contains(query)
        }
    }

    /// Begin scanning immediately and on a repeating timer.
    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Run one scan off the main actor and publish the sorted result, enriched
    /// with per-process stats gathered in the same background pass.
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        let scanner = self.scanner
        let collector = self.collector
        let (scanned, stats) = await Task.detached(priority: .utility) {
            let sockets = scanner.scan()
            let stats = collector.collect(pids: Set(sockets.map(\.pid)))
            return (sockets, stats)
        }.value
        entries = scanned.sorted {
            $0.port != $1.port ? $0.port < $1.port : $0.proto.rawValue < $1.proto.rawValue
        }
        processStats = stats
        lastScan = Date()
        isScanning = false
    }
}
