import SwiftUI

struct StorageView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Table(appState.storagePools) {
            TableColumn("Name") { (pool: StoragePool) in
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(pool.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("State") { (pool: StoragePool) in
                HStack(spacing: 4) {
                    Circle()
                        .fill(pool.state.lowercased() == "up" || pool.state.lowercased() == "ready" || pool.state.lowercased() == "active" ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(pool.state)
                        .font(.callout)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Type") { (pool: StoragePool) in
                Text(pool.type)
                    .font(.callout)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Usage") { pool in
                HStack(spacing: 8) {
                    ProgressView(value: pool.usedPercent, total: 100)
                        .frame(width: 80)
                        .tint(pool.usedPercent > 80 ? .red : pool.usedPercent > 60 ? .orange : .blue)
                    Text(String(format: "%.1f%%", pool.usedPercent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn("Total") { pool in
                Text(formatBytes(pool.totalBytes))
                    .font(.callout)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Used") { pool in
                Text(formatBytes(pool.usedBytes))
                    .font(.callout)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Allocated") { pool in
                Text(formatBytes(pool.allocBytes))
                    .font(.callout)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Zone") { (pool: StoragePool) in
                Text(pool.zone.isEmpty ? "-" : pool.zone)
                    .font(.callout)
            }
            .width(min: 60, ideal: 100)
        }
        .navigationTitle("Storage")
        .overlay {
            if appState.storagePools.isEmpty && !appState.isLoading {
                ContentUnavailableView(
                    "No Storage Pools",
                    systemImage: "externaldrive",
                    description: Text("No storage pools found in this environment.")
                )
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1024 {
            return String(format: "%.1f TB", gb / 1024)
        }
        return String(format: "%.1f GB", gb)
    }
}
