import SwiftUI
import Photos

/// Main gallery screen — mirrors Android's `MainActivity` + `GalleryAdapter`.
/// Shows a tree of Year → Month → (Camera / WhatsApp) → thumbnail grid.
struct GalleryView: View {

    @StateObject private var vm = GalleryViewModel()
    var scrollToMonthKey: String? = nil

    @State private var selectedItem: MediaItem? = nil
    @State private var showingPermissionAlert = false
    @State private var showingStats = false
    @State private var filterToast: String? = nil
    @State private var showScrollTop = false
    @State private var headerVisibleMonth: String? = nil
    @State private var footerVisibleMonth: String? = nil
    @State private var hintBob = false

    private func showFilterToast(_ message: String) {
        filterToast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if filterToast == message { filterToast = nil }
        }
    }

    var body: some View {
        Group {
            switch vm.authorizationStatus {
            case .authorized, .limited:
                VStack(spacing: 0) {
                    FilterChipsBar(
                        stats: vm.mediaStats,
                        includePhoto: vm.includePhoto,
                        includeVideo: vm.includeVideo,
                        includePdf: vm.includePdf,
                        includeAudio: vm.includeAudio,
                        onToggle: { vm.toggleTypeFilter($0) },
                        onRejected: { showFilterToast("At least one filter must be active") }
                    )
                    Divider()
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
            if vm.selectionMode {
                selectionBar
            } else if let undo = vm.pendingUndo {
                toast(message: undo.message) { vm.undoDelete() }
            } else if let done = vm.doneToast {
                toast(message: "\(done.label) marked done") { vm.undoMarkDone() }
            } else if vm.hideBarState != .none && vm.sortMode != .sizeAbsolute {
                hideMonthBar
            } else if let msg = filterToast {
                Text(msg)
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 2)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: vm.pendingUndo)
        .animation(.spring(duration: 0.3), value: vm.doneToast)
        .animation(.spring(duration: 0.3), value: filterToast)
        .animation(.spring(duration: 0.3), value: vm.selectionMode)
        .animation(.spring(duration: 0.3), value: vm.hideBarState)
        .navigationTitle(vm.selectionMode ? "\(vm.selectedIDs.count) selected" : "Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if vm.selectionMode {
                    Button("Cancel") { vm.exitSelection() }
                } else {
                    Button { showingStats = true } label: { Image(systemName: "info.circle") }
                }
            }
        }
        .sheet(isPresented: $showingStats) { StatsView() }
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

    // MARK: - Pinned Hide-month bar (spec §3)

    @ViewBuilder
    private var hideMonthBar: some View {
        switch vm.hideBarState {
        case .hide:
            Button {
                vm.hideOpenMonth()
            } label: {
                Label("Hide \(vm.hideBarMonthLabel)", systemImage: "checkmark")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 12).padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .scrollTeaser, .reviewHint:
            hintBar(text: vm.hideBarHintText)
        case .none:
            EmptyView()
        }
    }

    /// Amber coach hint with an animated down-chevron "wave" and a dismiss ✕.
    private func hintBar(text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.down")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
                .offset(y: hintBob ? 2 : -2)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: hintBob)
                .onAppear { hintBob = true }
            Text(text)
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            Spacer()
            Button { vm.dismissHideHint() } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(vm.selectedIDs.count) selected").font(.subheadline).bold()
                Text(Formatters.bytes(vm.selectedBytes)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                vm.shareSelected()
            } label: { Image(systemName: "square.and.arrow.up").font(.title3) }
                .disabled(vm.selectedIDs.isEmpty)
            Button(role: .destructive) {
                vm.deleteSelected()
            } label: { Image(systemName: "trash").font(.title3) }
                .disabled(vm.selectedIDs.isEmpty)
                .tint(.red)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, 12).padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                // Top anchor + scroll-offset probe for the scroll-to-top FAB.
                Color.clear.frame(height: 0).id("gallery-top")
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ScrollOffsetKey.self,
                                               value: geo.frame(in: .named("galleryScroll")).minY)
                    })
                LazyVStack(spacing: 0) {
                    ForEach(displayBlocks) { block in
                        switch block {
                        case .row(let item):
                            galleryRow(for: item).id(item.id)
                        case .grid(let cells, let blockID):
                            LazyVGrid(columns: gridColumns, spacing: 2) {
                                ForEach(cells, id: \.mediaItem.id) { cell in
                                    MediaThumbnailView(
                                        cell: cell,
                                        isSelecting: vm.selectionMode,
                                        isSelected: vm.selectedIDs.contains(cell.mediaItem.id),
                                        onTap: {
                                            if vm.selectionMode { vm.toggleSelection(cell.mediaItem.id) }
                                            else { selectedItem = cell.mediaItem }
                                        },
                                        onLongPress: { vm.enterSelection(cell.mediaItem.id) }
                                    )
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .id(blockID)
                        }
                    }
                }
            }
            .coordinateSpace(name: "galleryScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                // offset goes negative as content scrolls up; show FAB past ~3 rows.
                showScrollTop = offset < -400
            }
            .refreshable { vm.loadMedia(forceRefresh: true) }
            .onChange(of: scrollToMonthKey) { key in
                if let key { withAnimation { proxy.scrollTo("month-\(key)", anchor: .top) } }
            }
            .onChange(of: vm.scrollRequest) { req in
                // Opening a year / month / sub-group lands it at the top (§3 Landing, G-5/G-6).
                // Runs after the list relayout. (No sticky header yet, so anchor .top = offset 0;
                // revisit the below-sticky-strip offset from G-5 when the sticky header is built.)
                guard let req else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { proxy.scrollTo(req.id, anchor: .top) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollTop && !vm.selectionMode {
                    Button {
                        withAnimation { proxy.scrollTo("gallery-top", anchor: .top) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color.accentColor, in: Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .padding(20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: showScrollTop)
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
                .onAppear { if h.monthKey == vm.openMonthKey { headerVisibleMonth = h.monthKey; pushWalk() } }
                .onDisappear { if headerVisibleMonth == h.monthKey { headerVisibleMonth = nil; pushWalk() } }
        case .subHeader(let s):
            SubHeaderRow(sub: s) { vm.toggleSubGroupExpansion(s.subKey) }
        case .footer(let f):
            // Thin divider + the open month's bottom anchor for the walk gate. Visibility of
            // this row (and the month header) drives WalkLatch via evaluateWalk.
            Divider()
                .padding(.vertical, 6)
                .onAppear { footerVisibleMonth = f.monthKey; pushWalk() }
                .onDisappear { if footerVisibleMonth == f.monthKey { footerVisibleMonth = nil; pushWalk() } }
        case .media:
            EmptyView()   // media is rendered via grid blocks, never here
        }
    }

    /// Feed the open month's header/footer visibility into the walk gate.
    private func pushWalk() {
        guard let open = vm.openMonthKey else { return }
        vm.evaluateWalk(headerVisible: headerVisibleMonth == open,
                        footerVisible: footerVisibleMonth == open)
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

    // Sort lives in the sort bar; type filters in the FilterChipsBar. The toolbar's
    // ⓘ Stats / Refresh / Restore-last-deleted items (spec §3) are not built yet.
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

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
