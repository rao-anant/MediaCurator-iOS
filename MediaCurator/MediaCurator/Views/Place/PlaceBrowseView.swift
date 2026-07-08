import SwiftUI

/// Browse photos by place (spec §7). Mode A: flat city list. Mode B: country → state → city
/// drill-down with a teal breadcrumb. Selecting a city shows its photos → viewer.
struct PlaceBrowseView: View {
    let mode: PlaceBrowseViewModel.Mode
    @StateObject private var vm: PlaceBrowseViewModel
    @State private var selectedItem: MediaItem? = nil

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
                    Button(seg) { vm.popTo(depth: i) }
                        .font(.subheadline).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var placeList: some View {
        List(vm.list) { place in
            Button {
                vm.tapListItem(place.name)
            } label: {
                HStack {
                    Image(systemName: vm.listItemsAreCities ? "building.2" : "globe")
                        .foregroundStyle(Color.accentColor)
                    Text(place.name)
                    Spacer()
                    Text("\(place.count)").foregroundStyle(.secondary)
                    if !vm.listItemsAreCities {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
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

