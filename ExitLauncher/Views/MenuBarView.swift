import SwiftUI

enum PopoverScreen {
    case main
    case launch
    case settings
}

struct MenuBarView: View {
    @EnvironmentObject var manager: InstanceManager
    @State private var screen: PopoverScreen = .main

    var body: some View {
        Group {
            switch screen {
            case .main:
                mainView
            case .launch:
                LaunchNodeView(onDismiss: { screen = .main })
                    .environmentObject(manager)
            case .settings:
                SettingsView(onDismiss: { screen = .main })
            }
        }
        .task {
            await manager.loadState()
        }
    }

    // MARK: - Main View

    private var mainView: some View {
        VStack(spacing: 0) {
            // Connection status
            connectionStatus
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            // Active nodes
            if !manager.instances.isEmpty {
                activeNodesList
                    .padding(.vertical, 8)
                Divider()
            }

            // Error display
            if let error = manager.lastError {
                errorBanner(error)
                Divider()
            }

            // Actions
            actionButtons
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
        }
        .frame(width: 360)
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatus: some View {
        if let exitNode = manager.currentExitNode,
           let instance = manager.instances.first(where: { $0.tailscaleHostname == exitNode }) {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected via \(instance.regionName)")
                        .font(.headline)
                        .lineLimit(1)
                    Text(instance.tailscaleHostname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") {
                    Task { await manager.disconnectExitNode() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            HStack {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("Not connected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Active Nodes

    private var activeNodesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active Nodes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ForEach(manager.instances) { instance in
                NodeRowView(instance: instance)
                    .environmentObject(manager)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button {
                screen = .launch
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Launch New Node")
                    Spacer()
                }
            }
            .disabled(manager.isLaunching)

            Button {
                screen = .settings
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                }
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit ExitLauncher")
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }
}
