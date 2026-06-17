import SwiftUI
import AppKit

/// The dropdown shown when the menu bar icon is clicked.
struct MenuContentView: View {
    @EnvironmentObject var store: PortStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

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
                if store.containerizedCount > 0 {
                    Label("\(store.containerizedCount) in containers",
                          systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            Button {
                Task { await store.refresh(forceContainers: true) }
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
        let services = store.filteredServices
        if services.isEmpty {
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
                    ForEach(services) { service in
                        PortRow(service: service,
                                stats: store.processStats[service.pid],
                                container: store.container(for: service),
                                cpuPerCore: settings.cpuPerCore)
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Scans every \(Int(settings.refreshInterval))s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Portcall Settings")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Portcall")
            .keyboardShortcut("q")
        }
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One row in the services list, with a context menu of quick actions.
private struct PortRow: View {
    let service: ServiceRow
    let stats: ProcessStats?
    let container: ContainerInfo?
    let cpuPerCore: Bool

    var body: some View {
        HStack(spacing: 10) {
            exposureBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.command)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("PID \(service.pid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(service.displayAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(service.families.joined(separator: " · "))
                if let container {
                    Label(container.name, systemImage: "shippingbox.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .help("Image: \(container.image)")
                }
                if let stats, stats.hasUsage {
                    Text("CPU \(stats.cpuDisplay(perCore: cpuPerCore)) · \(stats.memoryDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if service.isDualStack {
                        Text("v4·v6")
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(service.proto.rawValue)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(":\(service.port)")
                    .font(.callout.monospaced())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if ProcessActions.webURL(for: service) != nil {
                Button("Open in Browser") { ProcessActions.openWeb(for: service) }
                Divider()
            }
            Button("Copy \(service.primaryAddress):\(service.port)") {
                ProcessActions.copy("\(service.primaryAddress):\(service.port)")
            }
            Button("Copy PID \(service.pid)") {
                ProcessActions.copy(String(service.pid))
            }
            if let path = stats?.executablePath {
                Button("Reveal Binary in Finder") {
                    ProcessActions.revealInFinder(path: path)
                }
                Button("Copy Executable Path") {
                    ProcessActions.copy(path)
                }
            }
            if let container {
                Divider()
                Button("Copy Container Name") { ProcessActions.copy(container.name) }
                Button("Copy Image") { ProcessActions.copy(container.image) }
            }
            Divider()
            Button("Terminate \(service.command) (SIGTERM)", role: .destructive) {
                ProcessActions.terminate(pid: service.pid)
            }
        }
    }

    private var exposureBadge: some View {
        Group {
            switch service.exposure {
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
        switch service.exposure {
        case .localhost: return "Localhost only — not reachable off this machine"
        case .specific: return "Bound to a specific interface"
        case .allInterfaces: return "Exposed on all interfaces — reachable from the network"
        }
    }
}
