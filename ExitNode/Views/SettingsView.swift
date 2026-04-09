import SwiftUI

struct SettingsView: View {
    var onDismiss: (() -> Void)?

    @State private var vultrAPIKey: String = ""
    @State private var tailscaleAuthKey: String = ""
    @State private var tailscaleAPIKey: String = ""
    @State private var saveStatus: String?
    @State private var isVultrKeyVisible = false
    @State private var isTailscaleAuthVisible = false
    @State private var isTailscaleAPIVisible = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                }
                Text("Settings")
                    .font(.headline)
                Spacer()
            }

            // Vultr
            keyField(
                label: "Vultr API Key",
                hint: "From my.vultr.com/settings/#settingsapi",
                text: $vultrAPIKey,
                isVisible: $isVultrKeyVisible
            )

            // Tailscale Auth Key
            keyField(
                label: "Tailscale Auth Key",
                hint: "For VPS nodes to join your tailnet (tskey-auth-...)",
                text: $tailscaleAuthKey,
                isVisible: $isTailscaleAuthVisible
            )

            // Tailscale API Key
            keyField(
                label: "Tailscale API Key",
                hint: "To auto-approve exit node routes (tskey-api-...)",
                text: $tailscaleAPIKey,
                isVisible: $isTailscaleAPIVisible
            )

            Spacer()

            // Save
            HStack {
                Button("Save") {
                    save()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let status = saveStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("Error") ? .red : .green)
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            vultrAPIKey = KeychainService.read(key: .vultrAPIKey) ?? ""
            tailscaleAuthKey = KeychainService.read(key: .tailscaleAuthKey) ?? ""
            tailscaleAPIKey = KeychainService.read(key: .tailscaleAPIKey) ?? ""
        }
    }

    private func keyField(label: String, hint: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Group {
                    if isVisible.wrappedValue {
                        TextField(label, text: text)
                    } else {
                        SecureField(label, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.caption)

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func save() {
        do {
            if !vultrAPIKey.isEmpty {
                try KeychainService.save(key: .vultrAPIKey, value: vultrAPIKey)
            }
            if !tailscaleAuthKey.isEmpty {
                try KeychainService.save(key: .tailscaleAuthKey, value: tailscaleAuthKey)
            }
            if !tailscaleAPIKey.isEmpty {
                try KeychainService.save(key: .tailscaleAPIKey, value: tailscaleAPIKey)
            }
            saveStatus = "Saved!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveStatus = nil
            }
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }
}
