import SwiftUI

struct SettingsView: View {
    var onDismiss: (() -> Void)?

    @State private var keys: [KeychainKey: String] = [:]
    @State private var visibility: [KeychainKey: Bool] = [:]
    @State private var saveStatus: String?

    private let fields: [(KeychainKey, String, String)] = [
        (.vultrAPIKey, "Vultr API Key", "my.vultr.com/settings/#settingsapi"),
        (.digitalOceanAPIKey, "Digital Ocean API Key", "cloud.digitalocean.com/account/api/tokens"),
        (.flyioAPIKey, "Fly.io API Token", "fly.io/docs/flyctl/tokens/"),
        (.awsCredentials, "AWS Credentials", "ACCESS_KEY_ID:SECRET_ACCESS_KEY (from IAM console)"),
        (.tailscaleAuthKey, "Tailscale Auth Key", "Reusable key for VPS to join tailnet (tskey-auth-...)"),
        (.tailscaleAPIKey, "Tailscale API Key", "Auto-approve exit node routes (tskey-api-...)"),
    ]

    var body: some View {
        VStack(spacing: 10) {
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

            ScrollView {
                VStack(spacing: 10) {
                    Text("Providers (add at least one)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(fields.prefix(4), id: \.0) { field in
                        keyField(key: field.0, label: field.1, hint: field.2)
                    }

                    Divider()

                    Text("Tailscale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(fields.suffix(2), id: \.0) { field in
                        keyField(key: field.0, label: field.1, hint: field.2)
                    }
                }
            }

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
            for field in fields {
                keys[field.0] = KeychainService.read(key: field.0) ?? ""
                visibility[field.0] = false
            }
        }
    }

    private func keyField(key: KeychainKey, label: String, hint: String) -> some View {
        let textBinding = Binding<String>(
            get: { keys[key] ?? "" },
            set: { keys[key] = $0 }
        )
        let isVisible = visibility[key] ?? false

        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Group {
                    if isVisible {
                        TextField(label, text: textBinding)
                    } else {
                        SecureField(label, text: textBinding)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.caption)

                Button {
                    visibility[key] = !isVisible
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
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
            for (key, value) in keys {
                if !value.isEmpty {
                    try KeychainService.save(key: key, value: value)
                }
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
