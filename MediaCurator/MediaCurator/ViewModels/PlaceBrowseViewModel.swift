import Foundation
import Combine

/// Drives the Place-browse screens (spec §7). Mode A = flat city list; Mode B = country → state
/// → city drill-down with a breadcrumb. Selecting a place shows its photos.
@MainActor
final class PlaceBrowseViewModel: ObservableObject {
    enum Mode { case cities, drill }

    @Published var sort: PlaceSort = .count
    @Published var isIndexing = false
    @Published var indexProgress: (done: Int, total: Int)? = nil

    // Drill state (nil country = country level; country set = state level; +state = city level).
    @Published var country: String? = nil
    @Published var state: String? = nil
    /// A selected city (with its country/state context) whose photos are shown.
    @Published var selectedCity: PlaceRecord? = nil

    @Published private(set) var list: [PlaceCount] = []
    @Published private(set) var photos: [MediaItem] = []

    let mode: Mode
    private let repo = MediaRepository()
    private let prefs = PreferencesManager()
    private var records: [PlaceRecord] = []
    private var placeByID: [String: PlaceRecord] = [:]
    private var media: [MediaItem] = []

    init(mode: Mode) { self.mode = mode }

    func load() {
        Task {
            media = await MediaCache.shared.get(repo: repo)
            let liveIDs = Set(media.map(\.id))

            // Kick indexing if enabled and there's unscanned work.
            if prefs.isPlaceSearchEnabled() {
                await runIndexingIfNeeded()
            }

            await PlaceStore.shared.ensureLoaded()
            records = await PlaceStore.shared.records(validIDs: liveIDs)
            placeByID = await PlaceStore.shared.placeByID(validIDs: liveIDs)
            rebuild()
        }
    }

    private func runIndexingIfNeeded() async {
        isIndexing = true
        defer { isIndexing = false; indexProgress = nil }
        let items = media
        _ = await PlaceIndexer.shared.index(items) { [weak self] done, total in
            self?.indexProgress = (done, total)
        }
    }

    func setSort(_ s: PlaceSort) { sort = s; rebuild() }

    // MARK: - Drill navigation

    func openCountry(_ name: String) {
        country = name; state = nil; selectedCity = nil
        // A country with no states (city-states) drills straight to cities.
        let hasStates = PlaceBrowse.states(records, country: name).contains { !$0.name.isEmpty }
        if !hasStates { /* city level via citiesInCountry handled in rebuild */ }
        rebuild()
    }
    func openState(_ name: String) { state = name; selectedCity = nil; rebuild() }
    func openCity(_ name: String) {
        // Resolve the full record for context (country/state) to filter photos precisely.
        let rec = records.first {
            $0.city == name &&
            (country == nil || $0.country == country) &&
            (state == nil || $0.state == state)
        } ?? PlaceRecord(city: name, state: state ?? "", country: country ?? "")
        selectedCity = rec
        photos = media.filter { m in
            guard let p = placeByID[m.id] else { return false }
            return p.city == rec.city
                && (rec.country.isEmpty || p.country == rec.country)
                && (rec.state.isEmpty || p.state == rec.state)
        }.sorted { $0.dateTaken > $1.dateTaken }
    }

    /// Breadcrumb segments for the current drill position (Mode B).
    var breadcrumb: [String] {
        var segs: [String] = []
        if let country { segs.append(country) }
        if let state, !state.isEmpty { segs.append(state) }
        if let selectedCity { segs.append(selectedCity.city) }
        return segs
    }

    func popTo(depth: Int) {
        // depth 0 = country list, 1 = state list, 2 = city list.
        selectedCity = nil
        if depth <= 0 { country = nil; state = nil }
        else if depth == 1 { state = nil }
        rebuild()
    }

    // MARK: - Build current list

    private func rebuild() {
        selectedCity = nil
        photos = []
        switch mode {
        case .cities:
            list = PlaceBrowse.cities(records, sort: sort)
        case .drill:
            if let country {
                let hasStates = PlaceBrowse.states(records, country: country).contains { !$0.name.isEmpty }
                if let state {
                    list = PlaceBrowse.citiesIn(records, country: country, state: state, sort: sort)
                } else if hasStates {
                    list = PlaceBrowse.states(records, country: country, sort: sort)
                } else {
                    list = PlaceBrowse.citiesInCountry(records, country: country, sort: sort)
                }
            } else {
                list = PlaceBrowse.countries(records, sort: sort)
            }
        }
    }

    /// Are we at the deepest level where list items are cities (tapping shows photos)?
    var listItemsAreCities: Bool {
        switch mode {
        case .cities: return true
        case .drill:
            guard let country else { return false }
            let hasStates = PlaceBrowse.states(records, country: country).contains { !$0.name.isEmpty }
            return state != nil || !hasStates
        }
    }

    func tapListItem(_ name: String) {
        if listItemsAreCities { openCity(name) }
        else if mode == .drill, country == nil { openCountry(name) }
        else { openState(name) }
    }
}
