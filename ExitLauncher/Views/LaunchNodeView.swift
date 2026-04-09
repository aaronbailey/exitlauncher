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

    @State private var allRegions: [Region] = []
    @State private var selectedRegion: Region?
    @State private var selectedTimer: DestroyTimer = .oneHour
    @State private var isLoadingRegions = true
    @State private var loadError: String?
    @State private var favorites: Set<String> = []
    @State private var enabledProviders: Set<Provider> = []

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
                        Task { await loadAllRegions() }
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
                if availableProviders.count > 1 {
                    providerFilter
                }
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
        .frame(width: 380)
        .task {
            favorites = FavoritesStore.load()
            await loadAllRegions()
            enabledProviders = Set(availableProviders)
        }
    }

    // MARK: - Provider Filter

    private var providerFilter: some View {
        HStack(spacing: 6) {
            ForEach(availableProviders) { provider in
                let isOn = enabledProviders.contains(provider)
                Button {
                    if isOn {
                        enabledProviders.remove(provider)
                    } else {
                        enabledProviders.insert(provider)
                    }
                    // Clear selection if it's now filtered out
                    if let sel = selectedRegion, !enabledProviders.contains(sel.provider) {
                        selectedRegion = nil
                    }
                } label: {
                    Text(provider.shortName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isOn ? .white : provider.badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isOn ? provider.badgeColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(provider.badgeColor, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Region Picker

    private var filteredRegions: [Region] {
        allRegions.filter { enabledProviders.contains($0.provider) }
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Region")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let regions = filteredRegions
            let favoriteRegions = regions.filter { favorites.contains(favoriteKey($0)) }
            let grouped = Dictionary(grouping: regions, by: \.normalizedContinent)
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
                        let sorted = (grouped[continent] ?? []).sorted { $0.displayName < $1.displayName }
                        ForEach(sorted) { region in
                            regionRow(region)
                                .tag(region)
                        }
                    }
                }
            }
            .listStyle(.bordered)
            .frame(height: 280)
        }
    }

    private func regionRow(_ region: Region) -> some View {
        let key = favoriteKey(region)
        return HStack(spacing: 6) {
            Text(region.displayName)
            providerBadge(region.provider)
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

    private func providerBadge(_ provider: Provider) -> some View {
        Text(provider.shortName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(provider.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
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

    private func loadAllRegions() async {
        isLoadingRegions = true
        loadError = nil

        var regions: [Region] = []

        // Load from all configured providers in parallel
        await withTaskGroup(of: [Region].self) { group in
            for provider in availableProviders {
                group.addTask {
                    (try? await manager.loadRegions(for: provider)) ?? []
                }
            }
            for await providerRegions in group {
                regions.append(contentsOf: providerRegions)
            }
        }

        if regions.isEmpty && !availableProviders.isEmpty {
            loadError = "Failed to load regions from any provider"
        }

        allRegions = regions
        isLoadingRegions = false
    }

    private func launch() async {
        guard let region = selectedRegion else { return }
        await manager.launchNode(region: region, destroyAfter: selectedTimer.interval)
        onDismiss()
    }
}
