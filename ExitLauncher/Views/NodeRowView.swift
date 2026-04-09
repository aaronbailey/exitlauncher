import SwiftUI

struct NodeRowView: View {
    let instance: VPSInstance
    @EnvironmentObject var manager: InstanceManager

    var body: some View {
        HStack {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.regionName)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(instance.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(instance.tailscaleHostname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if instance.status == .ready {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 8) {
                            Label(instance.uptimeFormatted, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let remaining = instance.timeRemainingFormatted {
                                Label(remaining, systemImage: "timer")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch instance.status {
        case .provisioning:
            ProgressView()
                .controlSize(.small)
                .frame(width: 12, height: 12)
        case .ready:
            let isActive = manager.currentExitNode == instance.tailscaleHostname
            Circle()
                .fill(isActive ? .green : .blue)
                .frame(width: 8, height: 8)
        case .destroying:
            ProgressView()
                .controlSize(.small)
                .frame(width: 12, height: 12)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch instance.status {
        case .ready:
            let isActive = manager.currentExitNode == instance.tailscaleHostname
            if !isActive {
                Button("Use") {
                    Task { await manager.useAsExitNode(instance) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button(role: .destructive) {
                Task { await manager.destroyNode(instance) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .provisioning:
            Text("Starting...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .destroying:
            Text("Removing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Button(role: .destructive) {
                Task { await manager.destroyNode(instance) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
