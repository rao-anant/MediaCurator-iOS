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
    /// Free-text place query (city / alias / state / country), diacritic-normalized.
    @Published var query = ""

    let mode: Mode
    private let repo = MediaRepository()
    private let prefs = PreferencesManager()
    private var records: [PlaceRecord] = []
    private var placeByID: [String: PlaceRecord] = [:]
    private var searchTokens: [String: [String]] = [:]
    private var media: [MediaItem] = []

    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Photos whose place tokens (city, aliases, state, country) match the query.
    var searchPhotos: [MediaItem] {
        media.filter { m in
            guard let toks = searchTokens[m.id] else { return false }
            return PlaceSearch.matchesAny(query: query, tokens: toks)
        }.sorted { $0.dateTaken > $1.dateTaken }
    }

    init(mode: Mode) { self.mode = mode }

    func load() {
        Task {
            // Exclude items staged for deletion (app trash). They're still in the Photos library
            // until the deletion commits, so without this a deleted photo resurfaces in the place
            // grid/counts on the next re-query. (Parity with Android's session-delete guard — here
            // the persisted staged set IS the guard, so it also survives across sessions.)
            let staged = prefs.getStagedForDeletion()
            media = (await MediaCache.shared.get(repo: repo)).filter { !staged.contains($0.id) }
            let liveIDs = Set(media.map(\.id))

            // Kick indexing if enabled and there's unscanned work.
            if prefs.isPlaceSearchEnabled() {
                await runIndexingIfNeeded()
            }

            await PlaceStore.shared.ensureLoaded()
            records = await PlaceStore.shared.records(validIDs: liveIDs)
            placeByID = await PlaceStore.shared.placeByID(validIDs: liveIDs)
            searchTokens = await PlaceStore.shared.searchIndex()
            // Preserve the open city across a refresh (e.g. after deleting a photo from its grid),
            // so the user stays on the grid — now minus the deleted item — instead of being
            // bounced back to the city list. rebuild() keeps country/state, only clearing the city.
            let keepCity = selectedCity
            rebuild()
            if let keepCity { openCity(keepCity.city) }
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

    /// Tap a breadcrumb segment → show THAT segment's children (keep the clicked level).
    /// Breadcrumb is [country, (state if any), (city if selected)].
    func tapBreadcrumb(_ index: Int) {
        let hasState = !(state ?? "").isEmpty
        if index == 0 {
            state = nil            // country segment → its states (or cities)
        } else if hasState && index == 1 {
            // state segment → its cities (keep state; rebuild clears the selected city)
        } else {
            return                 // city segment → already showing its photos
        }
        rebuild()
    }

    /// Walk up one drill level (for the ‹ back button — iOS has no system Back key).
    /// Returns false when already at the top, so the caller dismisses to Home.
    func goUp() -> Bool {
        if selectedCity != nil { rebuild(); return true }   // photos → the city list
        if !(state ?? "").isEmpty { state = nil; rebuild(); return true } // cities → states
        if country != nil { country = nil; rebuild(); return true }      // states → countries
        return false
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
