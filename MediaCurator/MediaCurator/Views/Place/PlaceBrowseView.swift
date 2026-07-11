import SwiftUI

/// Browse photos by place (spec §7). Mode A: flat city list. Mode B: country → state → city
/// drill-down with a teal breadcrumb. Selecting a city shows its photos → viewer.
struct PlaceBrowseView: View {
    let mode: PlaceBrowseViewModel.Mode
    @StateObject private var vm: PlaceBrowseViewModel
    @State private var selectedItem: MediaItem? = nil
    @Environment(\.dismiss) private var dismiss

    init(mode: PlaceBrowseViewModel.Mode) {
        self.mode = mode
        _vm = StateObject(wrappedValue: PlaceBrowseViewModel(mode: mode))
    }

    private let photoCols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            if mode == .drill && !vm.breadcrumb.isEmpty { breadcrumbBar }
            if vm.selectedCity == nil { sortBar }

            if let p = vm.indexProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1))) {
                    Text("Finding places… \(p.done)/\(p.total)").font(.caption)
                }
                .padding(.horizontal)
            }

            if vm.searching {
                searchResults
            } else if vm.selectedCity != nil {
                photoGrid(vm.photos)
            } else if vm.list.isEmpty {
                emptyState
            } else {
                placeList
            }
        }
        .navigationTitle(mode == .cities ? "Browse by location" : "By location")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // ‹ walks up one drill level (photos → city → state → country), exiting to Home
                // only at the top. iOS has no system Back key, so this mirrors Android's Back.
                Button { if !vm.goUp() { dismiss() } } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // Jump straight to Home from anywhere in the drill (no repeated back-taps).
                Button { dismiss() } label: { Image(systemName: "house") }
            }
        }
        .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search a city, state, or country")
        .onAppear { vm.load() }
        .fullScreenCover(item: $selectedItem) { item in
            SimpleMediaViewer(items: vm.searching ? vm.searchPhotos : vm.photos, startingID: item.id)
        }
    }

    private var sortBar: some View {
        Picker("Sort", selection: Binding(get: { vm.sort }, set: { vm.setSort($0) })) {
            Text("Most photos").tag(PlaceSort.count)
            Text("A–Z").tag(PlaceSort.name)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(vm.breadcrumb.enumerated()), id: \.offset) { i, seg in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                    Button(seg) { vm.tapBreadcrumb(i) }
                        .font(.subheadline).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    // Adaptive so chips stay a sensible width: ~2 columns on iPhone, several on iPad, instead of
    // two half-screen-wide chips on a tablet.
    private let chipCols = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10)]

    private var placeList: some View {
        ScrollView {
            LazyVGrid(columns: chipCols, spacing: 10) {
                ForEach(vm.list) { place in
                    Button { vm.tapListItem(place.name) } label: { chip(for: place) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    /// One colored chip for a city (🏙️), country (real flag) or state (🚩). Drill levels
    /// (country/state) carry a chevron; cities are terminal.
    private func chip(for place: PlaceCount) -> some View {
        let c = ChipPalette.color(for: place.name)
        let isCountryLevel = mode == .drill && vm.country == nil
        let emoji = vm.listItemsAreCities ? "🏙️" : (isCountryLevel ? CountryFlags.flag(for: place.name) : "🚩")
        return HStack(spacing: 6) {
            Text(emoji).font(.subheadline)
            Text("\(place.name) · \(place.count)")
                .font(.subheadline).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if !vm.listItemsAreCities {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(red: c.0, green: c.1, blue: c.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private func photoGrid(_ items: [MediaItem]) -> some View {
        SelectablePhotoGrid(items: items,
                            onOpen: { selectedItem = $0 },
                            onDeleted: { vm.load() })
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = vm.searchPhotos
        if results.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "magnifyingglass").font(.title).foregroundStyle(.secondary)
                Text("No photos match “\(vm.query)”").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            photoGrid(results)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(vm.isIndexing ? "Finding places in your photos…" : "No places found yet")
                .font(.headline)
            Text("Only photos with GPS location can be placed on a map. Screenshots and downloaded images usually have none.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

