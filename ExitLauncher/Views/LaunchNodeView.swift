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

    @State private var regions: [Region] = []
    @State private var selectedRegion: Region?
    @State private var selectedTimer: DestroyTimer = .oneHour
    @State private var isLoadingRegions = true
    @State private var loadError: String?
    @State private var favorites: Set<String> = []

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
                        Task { await loadRegions() }
                    }
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
            await loadRegions()
        }
    }

    // MARK: - Region Picker

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Region")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let favoriteRegions = regions.filter { favorites.contains($0.id) }
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
        HStack {
            Text(region.displayName)
            Spacer()
            Button {
                toggleFavorite(region.id)
            } label: {
                Image(systemName: favorites.contains(region.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.contains(region.id) ? .yellow : .secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
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
            regions = try await manager.vultr.listRegions()
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
