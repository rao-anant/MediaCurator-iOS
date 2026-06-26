import SwiftUI
import Photos

/// Main gallery screen — mirrors Android's `MainActivity` + `GalleryAdapter`.
/// Shows a tree of Year → Month → (Camera / WhatsApp) → thumbnail grid.
struct GalleryView: View {

    @StateObject private var vm = GalleryViewModel()
    var scrollToMonthKey: String? = nil

    @State private var selectedItem: MediaItem? = nil
    @State private var showingPermissionAlert = false

    var body: some View {
        Group {
            switch vm.authorizationStatus {
            case .authorized, .limited:
                VStack(spacing: 0) {
                    sortBar
                    galleryContent
                }
            case .denied, .restricted:
                permissionDeniedView
            case .notDetermined:
                Color.clear.onAppear { Task { await vm.requestAuthorization() } }
            @unknown default:
                Color.clear
            }
        }
        .overlay(alignment: .bottom) {
            if let undo = vm.pendingUndo {
                toast(message: undo.message) { vm.undoDelete() }
            } else if let done = vm.doneToast {
                toast(message: "\(done.label) marked done") { vm.undoMarkDone() }
            }
        }
        .animation(.spring(duration: 0.3), value: vm.pendingUndo)
        .animation(.spring(duration: 0.3), value: vm.doneToast)
        .navigationTitle("Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { galleryToolbar }
        .onAppear {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            vm.authorizationStatus = status
            if status == .authorized || status == .limited {
                vm.loadMedia(forceRefresh: false)
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            MediaViewerView(vm: vm, startingID: item.id)
        }
    }

    // MARK: - Sort bar

    /// Always-visible sort indicator at the top of the gallery — shows the current order
    /// and lets the user change it (mirrors Android's gallery sort header).
    private var sortBar: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        vm.setSortMode(mode)
                    } label: {
                        if vm.sortMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sorted by \(vm.sortMode.displayName)")
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down").font(.caption2)
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)
            Divider()
        }
    }

    // MARK: - Toast

    private func toast(message: String, undo: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Text(message).font(.subheadline)
            Button("Undo", action: undo).font(.subheadline.bold())
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 2)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Gallery content

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    private var galleryContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.isLoading && vm.galleryItems.isEmpty {
                    ProgressView("Scanning library…").padding(.top, 40)
                }
                LazyVStack(spacing: 0) {
                    ForEach(displayBlocks) { block in
                        switch block {
                        case .row(let item):
                            galleryRow(for: item).id(item.id)
                        case .grid(let cells, let blockID):
                            LazyVGrid(columns: gridColumns, spacing: 2) {
                                ForEach(cells, id: \.mediaItem.id) { cell in
                                    MediaThumbnailView(cell: cell) { selectedItem = cell.mediaItem }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .id(blockID)
                        }
                    }
                }
            }
            .refreshable { vm.loadMedia(forceRefresh: true) }
            .onChange(of: scrollToMonthKey) { key in
                if let key { withAnimation { proxy.scrollTo("month-\(key)", anchor: .top) } }
            }
        }
    }

    /// Headers/footers render full-width; runs of consecutive media cells are grouped so
    /// they can be laid out in a grid instead of one-per-row.
    private enum DisplayBlock: Identifiable {
        case row(GalleryItem)
        case grid([GalleryItem.MediaCell], id: String)
        var id: String {
            switch self {
            case .row(let item):    return item.id
            case .grid(_, let id):  return id
            }
        }
    }

    private var displayBlocks: [DisplayBlock] {
        var blocks: [DisplayBlock] = []
        var run: [GalleryItem.MediaCell] = []
        func flush() {
            guard let first = run.first else { return }
            blocks.append(.grid(run, id: "grid-\(first.mediaItem.id)"))
            run = []
        }
        for item in vm.galleryItems {
            if case .media(let cell) = item {
                run.append(cell)
            } else {
                flush()
                blocks.append(.row(item))
            }
        }
        flush()
        return blocks
    }

    @ViewBuilder
    private func galleryRow(for item: GalleryItem) -> some View {
        switch item {
        case .yearHeader(let y):
            YearHeaderRow(header: y) { vm.toggleYearExpansion(y.year) }
        case .header(let h):
            MonthHeaderRow(header: h, onTap: { vm.toggleMonthExpansion(h.monthKey) })
        case .subHeader(let s):
            SubHeaderRow(sub: s) { vm.toggleSubGroupExpansion(s.subKey) }
        case .footer(let f):
            Button {
                vm.markMonthDone(key: f.monthKey)
            } label: {
                Label("Hide Month from this app", systemImage: "eye.slash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        case .media:
            EmptyView()   // media is rendered via grid blocks, never here
        }
    }

    // MARK: - Permission denied

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.slash").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Photos Access Required")
                .font(.title2).bold()
            Text("MediaCurator needs access to your photo library to show and curate your media.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var galleryToolbar: some ToolbarContent {
        // Sort lives in the always-visible sort bar; the toolbar keeps just the type filter.
        ToolbarItem(placement: .navigationBarTrailing) {
            // Type filter chips
            Menu {
                Toggle("Photos",  isOn: Binding(get: { vm.includePhoto }, set: { vm.setIncludePhoto($0) }))
                Toggle("Videos",  isOn: Binding(get: { vm.includeVideo }, set: { vm.setIncludeVideo($0) }))
                Toggle("PDFs",    isOn: Binding(get: { vm.includePdf },   set: { vm.setIncludePdf($0) }))
                Toggle("Audio",   isOn: Binding(get: { vm.includeAudio }, set: { vm.setIncludeAudio($0) }))
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

// MARK: - SortMode display names

extension SortMode {
    var displayName: String {
        switch self {
        case .dateNewest:      return "Newest first"
        case .dateOldest:      return "Oldest first"
        case .sizeAbsolute:    return "Largest files"
        case .sizeWithinMonth: return "Largest within month"
        case .countPerMonth:   return "Most items per month"
        }
    }
}
