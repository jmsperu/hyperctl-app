import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var runningVMs: Int { appState.vms.filter { $0.state == .running }.count }
    private var stoppedVMs: Int { appState.vms.filter { $0.state == .stopped }.count }
    private var otherVMs: Int { appState.vms.count - runningVMs - stoppedVMs }

    private var hostsUp: Int { appState.hosts.filter { $0.state.lowercased() == "up" }.count }
    private var hostsDown: Int { appState.hosts.count - hostsUp }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                // VM Summary
                DashboardCard(title: "Virtual Machines", icon: "desktopcomputer") {
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatBadge(value: appState.vms.count, label: "Total", color: .primary)
                            StatBadge(value: runningVMs, label: "Running", color: .green)
                            StatBadge(value: stoppedVMs, label: "Stopped", color: .red)
                            if otherVMs > 0 {
                                StatBadge(value: otherVMs, label: "Other", color: .orange)
                            }
                        }

                        if !appState.vms.isEmpty {
                            Chart {
                                SectorMark(angle: .value("Running", runningVMs), innerRadius: .ratio(0.6))
                                    .foregroundStyle(.green)
                                SectorMark(angle: .value("Stopped", stoppedVMs), innerRadius: .ratio(0.6))
                                    .foregroundStyle(.red)
                                if otherVMs > 0 {
                                    SectorMark(angle: .value("Other", otherVMs), innerRadius: .ratio(0.6))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                }

                // Host Summary
                DashboardCard(title: "Hosts", icon: "server.rack") {
                    VStack(spacing: 12) {
                        HStack(spacing: 24) {
                            StatBadge(value: appState.hosts.count, label: "Total", color: .primary)
                            StatBadge(value: hostsUp, label: "Up", color: .green)
                            StatBadge(value: hostsDown, label: "Down", color: .red)
                        }

                        if !appState.hosts.isEmpty {
                            Chart(appState.hosts, id: \.id) { host in
                                let memPercent = host.memoryTotal > 0
                                    ? Double(host.memoryUsed) / Double(host.memoryTotal) * 100
                                    : 0
                                BarMark(
                                    x: .value("Host", host.name),
                                    y: .value("Memory %", memPercent)
                                )
                                .foregroundStyle(memPercent > 80 ? .red : memPercent > 60 ? .orange : .blue)
                            }
                            .chartYScale(domain: 0...100)
                            .chartYAxisLabel("Memory %")
                            .frame(height: 120)
                        }
                    }
                }

                // Storage Summary
                DashboardCard(title: "Storage", icon: "externaldrive") {
                    VStack(spacing: 8) {
                        if appState.storagePools.isEmpty {
                            Text("No storage pools")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(appState.storagePools) { pool in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(pool.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.1f%%", pool.usedPercent))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: pool.usedPercent, total: 100)
                                        .tint(pool.usedPercent > 80 ? .red : pool.usedPercent > 60 ? .orange : .blue)
                                }
                            }
                        }
                    }
                }

                // Network Summary
                DashboardCard(title: "Networks", icon: "network") {
                    VStack(spacing: 8) {
                        StatBadge(value: appState.networks.count, label: "Total Networks", color: .blue)

                        if !appState.networks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(appState.networks.prefix(6)) { net in
                                    HStack {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 6, height: 6)
                                        Text(net.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(net.type)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if appState.networks.count > 6 {
                                    Text("+\(appState.networks.count - 6) more")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

// MARK: - Dashboard Card

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
