import SwiftUI

enum DestroyTimer: String, CaseIterable, Identifiable {
    case none = "Manual"
    case oneHour = "1 Hour"
    case fourHours = "4 Hours"
    case twentyFourHours = "24 Hours"

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .none: return nil
        case .oneHour: return 3600
        case .fourHours: return 14400
        case .twentyFourHours: return 86400
        }
    }
}

struct FavoritesStore {
    private static let key = "favoriteRegions"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ favorites: Set<String>) {
        UserDefaults.standard.set(Array(favorites), forKey: key)
    }
}

struct LaunchNodeView: View {
    @EnvironmentObject var manager: InstanceManager
    var onDismiss: () -> Void

    @State private var selectedProvider: Provider = .vultr
    @State private var regions: [Region] = []
    @State private var selectedRegion: Region?
    @State private var selectedTimer: DestroyTimer = .oneHour
    @State private var isLoadingRegions = true
    @State private var loadError: String?
    @State private var favorites: Set<String> = []

    /// Only show providers that have an API key configured
    private var availableProviders: [Provider] {
        Provider.allCases.filter { provider in
            let key = KeychainService.read(key: provider.keychainKey)
            return key != nil && !key!.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text("Launch New Exit Node")
                    .font(.headline)
                Spacer()
            }

            // Provider picker (only if multiple configured)
            if availableProviders.count > 1 {
                providerPicker
            }

            if isLoadingRegions {
                ProgressView("Loading regions...")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadRegions() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if availableProviders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "key")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No provider API keys configured.\nAdd at least one in Settings.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                regionPicker
                timerPicker
            }

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if manager.isLaunching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Launch") {
                    Task { await launch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedRegion == nil || manager.isLaunching)
            }
        }
        .padding(16)
        .frame(width: 360)
        .task {
            favorites = FavoritesStore.load()
            if let first = availableProviders.first {
                selectedProvider = first
            }
            await loadRegions()
        }
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Picker("Provider", selection: $selectedProvider) {
            ForEach(availableProviders) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedProvider) { _ in
            selectedRegion = nil
            Task { await loadRegions() }
        }
    }

    // MARK: - Region Picker

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Region")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Favorites use provider-prefixed IDs to avoid collisions
            let favoriteRegions = regions.filter { favorites.contains(favoriteKey($0)) }
            let grouped = Dictionary(grouping: regions, by: \.continent)
            let sortedContinents = grouped.keys.sorted()

            List(selection: $selectedRegion) {
                if !favoriteRegions.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteRegions) { region in
                            regionRow(region)
                                .tag(region)
                        }
                    }
                }

                ForEach(sortedContinents, id: \.self) { continent in
                    Section(continent) {
                        ForEach(grouped[continent] ?? []) { region in
                            regionRow(region)
                                .tag(region)
                        }
                    }
                }
            }
            .listStyle(.bordered)
            .frame(height: 250)
        }
    }

    private func regionRow(_ region: Region) -> some View {
        let key = favoriteKey(region)
        return HStack {
            Text(region.displayName)
            Spacer()
            Button {
                toggleFavorite(key)
            } label: {
                Image(systemName: favorites.contains(key) ? "star.fill" : "star")
                    .foregroundStyle(favorites.contains(key) ? .yellow : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
    }

    private func favoriteKey(_ region: Region) -> String {
        "\(region.provider.rawValue):\(region.id)"
    }

    private func toggleFavorite(_ key: String) {
        if favorites.contains(key) {
            favorites.remove(key)
        } else {
            favorites.insert(key)
        }
        FavoritesStore.save(favorites)
    }

    // MARK: - Timer Picker

    private var timerPicker: some View {
        HStack {
            Text("Auto-destroy:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedTimer) {
                ForEach(DestroyTimer.allCases) { timer in
                    Text(timer.rawValue).tag(timer)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Actions

    private func loadRegions() async {
        isLoadingRegions = true
        loadError = nil
        do {
            regions = try await manager.loadRegions(for: selectedProvider)
            isLoadingRegions = false
        } catch {
            loadError = error.localizedDescription
            isLoadingRegions = false
        }
    }

    private func launch() async {
        guard let region = selectedRegion else { return }
        await manager.launchNode(region: region, destroyAfter: selectedTimer.interval)
        onDismiss()
    }
}
