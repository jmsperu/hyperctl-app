import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Table(appState.networks) {
            TableColumn("Name") { (net: HyperNetwork) in
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(net.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("State") { (net: HyperNetwork) in
                HStack(spacing: 4) {
                    Circle()
                        .fill(net.state.lowercased() == "active" || net.state.lowercased() == "allocated" || net.state.lowercased() == "implemented" ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(net.state)
                        .font(.callout)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Type") { (net: HyperNetwork) in
                Text(net.type)
                    .font(.callout)
            }
            .width(min: 60, ideal: 100)

            TableColumn("CIDR") { (net: HyperNetwork) in
                Text(net.cidr.isEmpty ? "-" : net.cidr)
                    .font(.callout.monospaced())
            }
            .width(min: 100, ideal: 140)

            TableColumn("Gateway") { (net: HyperNetwork) in
                Text(net.gateway.isEmpty ? "-" : net.gateway)
                    .font(.callout.monospaced())
            }
            .width(min: 100, ideal: 130)

            TableColumn("VLAN") { (net: HyperNetwork) in
                Text(net.vlan.isEmpty ? "-" : net.vlan)
                    .font(.callout)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Zone") { (net: HyperNetwork) in
                Text(net.zone.isEmpty ? "-" : net.zone)
                    .font(.callout)
            }
            .width(min: 60, ideal: 100)
        }
        .navigationTitle("Networks")
        .overlay {
            if appState.networks.isEmpty && !appState.isLoading {
                ContentUnavailableView(
                    "No Networks",
                    systemImage: "network",
                    description: Text("No networks found in this environment.")
                )
            }
        }
    }
}
