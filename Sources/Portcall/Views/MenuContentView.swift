import SwiftUI
import AppKit

/// The dropdown shown when the menu bar icon is clicked.
struct MenuContentView: View {
    @EnvironmentObject var store: PortStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            listBody
            Divider()
            footer
        }
        .frame(width: 400, height: 480)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(store.listeningCount) listening service\(store.listeningCount == 1 ? "" : "s")")
                    .font(.headline)
                if store.exposedCount > 0 {
                    Label("\(store.exposedCount) exposed to network",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let last = store.lastScan {
                    Text("Updated \(last.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .disabled(store.isScanning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search port, process, PID, address", text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var listBody: some View {
        let entries = store.filteredEntries
        if entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: store.searchText.isEmpty ? "checkmark.shield" : "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(store.searchText.isEmpty ? "No listening services" : "No matches")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        PortRow(entry: entry, stats: store.processStats[entry.pid])
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Scans every \(Int(store.refreshInterval))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One row in the services list, with a context menu of quick actions.
private struct PortRow: View {
    let entry: PortEntry
    let stats: ProcessStats?

    var body: some View {
        HStack(spacing: 10) {
            exposureBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.command)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("PID \(entry.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.displayAddress):\(entry.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let stats, stats.hasUsage {
                    Text("CPU \(stats.cpuDisplay) · \(stats.memoryDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.proto.rawValue)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(":\(entry.port)")
                    .font(.callout.monospaced())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if ProcessActions.webURL(for: entry) != nil {
                Button("Open in Browser") { ProcessActions.openWeb(for: entry) }
                Divider()
            }
            Button("Copy \(entry.displayAddress):\(entry.port)") {
                ProcessActions.copy("\(entry.displayAddress):\(entry.port)")
            }
            Button("Copy PID \(entry.pid)") {
                ProcessActions.copy(String(entry.pid))
            }
            if let path = stats?.executablePath {
                Button("Reveal Binary in Finder") {
                    ProcessActions.revealInFinder(path: path)
                }
                Button("Copy Executable Path") {
                    ProcessActions.copy(path)
                }
            }
            Divider()
            Button("Terminate \(entry.command) (SIGTERM)", role: .destructive) {
                ProcessActions.terminate(pid: entry.pid)
            }
        }
    }

    private var exposureBadge: some View {
        Group {
            switch entry.exposure {
            case .localhost:
                Image(systemName: "lock.fill").foregroundStyle(.green)
            case .specific:
                Image(systemName: "globe").foregroundStyle(.yellow)
            case .allInterfaces:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .font(.body)
        .frame(width: 18)
        .help(exposureHelp)
    }

    private var exposureHelp: String {
        switch entry.exposure {
        case .localhost: return "Localhost only — not reachable off this machine"
        case .specific: return "Bound to a specific interface"
        case .allInterfaces: return "Exposed on all interfaces — reachable from the network"
        }
    }
}
