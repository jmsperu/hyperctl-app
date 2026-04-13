import SwiftUI

struct HostListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Table(appState.hosts) {
            TableColumn("Name") { (host: HyperHost) in
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(host.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("State") { (host: HyperHost) in
                let isUp = host.state.lowercased() == "up"
                HStack(spacing: 4) {
                    Circle()
                        .fill(isUp ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(host.state)
                        .font(.callout)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Hypervisor") { (host: HyperHost) in
                Text(host.hypervisor)
                    .font(.callout)
            }
            .width(min: 80, ideal: 100)

            TableColumn("CPUs") { host in
                Text("\(host.cpus)")
                    .font(.callout)
            }
            .width(50)

            TableColumn("CPU Used") { host in
                let percent = parseCPUPercent(host.cpuUsed)
                HStack(spacing: 6) {
                    ProgressView(value: percent, total: 100)
                        .frame(width: 60)
                        .tint(percent > 80 ? .red : percent > 60 ? .orange : .blue)
                    Text(host.cpuUsed.isEmpty ? "-" : host.cpuUsed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("Memory") { host in
                let memPercent = host.memoryTotal > 0
                    ? Double(host.memoryUsed) / Double(host.memoryTotal) * 100
                    : 0
                HStack(spacing: 6) {
                    ProgressView(value: memPercent, total: 100)
                        .frame(width: 60)
                        .tint(memPercent > 80 ? .red : memPercent > 60 ? .orange : .blue)
                    Text(String(format: "%.0f%%", memPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .width(min: 100, ideal: 130)

            TableColumn("Zone") { (host: HyperHost) in
                Text(host.zone.isEmpty ? "-" : host.zone)
                    .font(.callout)
            }
            .width(min: 60, ideal: 100)

            TableColumn("Cluster") { (host: HyperHost) in
                Text(host.cluster.isEmpty ? "-" : host.cluster)
                    .font(.callout)
            }
            .width(min: 60, ideal: 100)
        }
        .navigationTitle("Hosts")
        .overlay {
            if appState.hosts.isEmpty && !appState.isLoading {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "server.rack",
                    description: Text("No hosts found in this environment.")
                )
            }
        }
    }

    private func parseCPUPercent(_ str: String) -> Double {
        let cleaned = str.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }
}
