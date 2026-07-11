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
    @State private var headerPositions: [String: CGFloat] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    /// Pixel size to request each thumbnail at — the cell's point width (viewport ÷ 4 columns)
    /// times the screen scale. Computed once from the stable viewport width so the request key
    /// doesn't change during a month's expand animation (which caused thumbnails to flicker).
    private var cellTargetPx: CGFloat {
        let w = viewportWidth > 0 ? viewportWidth : 400
        return max(240, (w / 4) * displayScale)
    }

    /// Sticky context (spec §3): the year always, the month when scrolled into one. Derived from
    /// the closest header that has scrolled to/above the top. Hidden in flat size-sort mode.
    private var stickyYear: String? {
        guard vm.sortMode != .sizeAbsolute else { return nil }
        // An open month pins its own year (avoids the strip going blank / wrong for short months).
        if let open = vm.openMonthKey { return String(open.prefix(4)) }
        let ys = headerPositions.filter { $0.key.hasPrefix("Y:") && $0.value <= 0 }
        guard let top = ys.max(by: { $0.value < $1.value }) else { return nil }
        return String(top.key.dropFirst(2))
    }
    private var stickyMonthLabel: String? {
        guard vm.sortMode != .sizeAbsolute else { return nil }
        // When a month is expanded, always show its label — derived straight from the open-month
        // key (same source as the Hide bar), NOT from on-screen header positions. In a long month
        // the month header scrolls off the top and the lazy list drops it, which previously made
        // the label vanish so only the year showed (see chandrika.jpg).
        if let open = vm.openMonthKey {
            return Formatters.monthLabel(from: open)
        }
        guard let year = stickyYear else { return nil }
        let ms = headerPositions.filter { $0.key.hasPrefix("M:\(year)-") && $0.value <= 0 }
        guard let top = ms.max(by: { $0.value < $1.value }) else { return nil }
        return top.key.split(separator: "|").last.map(String.init)
    }

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
                        // In selection mode the action bar sits BELOW the grid and insets it,
                        // rather than overlaying the last row (parity with Android a29).
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if vm.selectionMode { selectionBar }
                        }
                }
            case .denied, .restricted:
                permissionDeniedView
            case .notDetermined:
                Color.clear.onAppear { Task { await vm.requestAuthorization() } }
            @unknown default:
                Color.clear
            }
        }
        // Selection bar is handled via safeAreaInset above (it must not occlude the grid). These
        // are transient floating elements and only show when NOT selecting.
        .overlay(alignment: .bottom) {
            if !vm.selectionMode {
                if let undo = vm.pendingUndo {
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
            if !vm.selectionMode {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { vm.loadMedia(forceRefresh: true) } label: { Image(systemName: "arrow.clockwise") }
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

    // MARK: - Sticky header (spec §3)

    @ViewBuilder
    private var stickyHeader: some View {
        if let year = stickyYear, !vm.selectionMode {
            VStack(spacing: 0) {
                Button {
                    if let y = Int(year) { vm.toggleYearExpansion(y) }
                } label: {
                    HStack {
                        Text(year).font(.subheadline).bold()
                        Spacer()
                        Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Color(.systemBackground).opacity(0.96))
                }
                .buttonStyle(.plain)
                if let month = stickyMonthLabel {
                    Button {
                        // Collapse the open month if this sticky month is it.
                        if let key = vm.openMonthKey { vm.toggleMonthExpansion(key) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(month).font(.subheadline).foregroundStyle(.primary)
                                // Count + size in a smaller font (matches Android's month strip).
                                if vm.openMonthKey != nil {
                                    Text("\(Formatters.countShort(vm.openMonthCount)) photos · \(Formatters.bytes(vm.openMonthBytes))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .background(Color(.systemBackground).opacity(0.96))
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
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

    /// Amber coach hint with an animated 3-chevron "wave" and a dismiss ✕.
    private func hintBar(text: String) -> some View {
        HStack(spacing: 12) {
            ChevronWave()
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

    /// Centered empty-state message when the gallery has no rows (spec §3).
    private var galleryEmptyMessage: String? {
        let s = vm.mediaStats
        let total = s.totalPhotos + s.totalVideos + s.totalPdfs + s.totalAudios
        if total == 0 { return "No media found on this device." }
        let visible = s.visiblePhotos + s.visibleVideos + s.visiblePdfs + s.visibleAudios
        if visible == 0 { return "All months are hidden! Use ‘Hidden months’ on the Home screen to bring them back." }
        return "No items match the current filter. Tap the chips above to show more types."
    }

    private var galleryContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.isLoading && vm.galleryItems.isEmpty {
                    ProgressView("Scanning library…").padding(.top, 40)
                } else if vm.galleryItems.isEmpty, let msg = galleryEmptyMessage {
                    Text(msg)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40).padding(.top, 80)
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
                                        targetPx: cellTargetPx,
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
                    // Bottom inset so the last month's footer scrolls clear of the pinned
                    // Hide/hint bar — otherwise the footer sits behind the bar, its onAppear
                    // never fires, and the walk gate can't register "reached the end" (spec §3
                    // "never covers content"; fixes Hide not appearing at the true bottom).
                    Color.clear.frame(height: 96)
                }
            }
            .coordinateSpace(name: "galleryScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                // offset goes negative as content scrolls up; show FAB past ~3 rows.
                showScrollTop = offset < -400
            }
            .onPreferenceChange(HeaderPosKey.self) { pos in
                headerPositions = pos
                // Continuous walk-gate evaluation from real positions (robust at the true bottom).
                guard let open = vm.openMonthKey, viewportHeight > 0 else { return }
                let headerY = pos.first { $0.key.hasPrefix("M:\(open)|") }?.value
                let footerY = pos["F:\(open)"]
                let headerVisible = (headerY ?? .greatestFiniteMagnitude) <= 8   // header reached the top
                let footerVisible = footerY.map { $0 > 0 && $0 < viewportHeight } ?? false
                vm.evaluateWalk(headerVisible: headerVisible, footerVisible: footerVisible)
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { viewportHeight = g.size.height; viewportWidth = g.size.width }
                                     .onChange(of: g.size.height) { viewportHeight = $0 }
                                     .onChange(of: g.size.width) { viewportWidth = $0 }
            })
            .overlay(alignment: .top) { stickyHeader }
            .refreshable { vm.loadMedia(forceRefresh: true) }
            .onChange(of: scrollToMonthKey) { key in
                if let key { withAnimation { proxy.scrollTo("month-\(key)", anchor: .top) } }
            }
            .onChange(of: vm.scrollRequest) { req in
                // Opening a year / month / sub-group lands it at the top (§3 Landing, G-5/G-6).
                // The list is mid-relayout (the accordion collapses other months while the tapped
                // level's rows appear), so a single early scroll can miss the target's final
                // position. Nudge it a few times across the settle window — once the target is at
                // the top the later calls are no-ops, so it lands reliably without visible jank.
                guard let req else { return }
                for delay in [0.05, 0.2, 0.4, 0.65] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(req.id, anchor: .top) }
                    }
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
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeaderPosKey.self,
                                           value: ["Y:\(y.year)": g.frame(in: .named("galleryScroll")).minY])
                })
        case .header(let h):
            MonthHeaderRow(header: h, onTap: { vm.toggleMonthExpansion(h.monthKey) })
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeaderPosKey.self,
                                           value: ["M:\(h.monthKey)|\(h.label)": g.frame(in: .named("galleryScroll")).minY])
                })
        case .subHeader(let s):
            SubHeaderRow(sub: s) { vm.toggleSubGroupExpansion(s.subKey) }
        case .footer(let f):
            // Thin divider + the open month's bottom anchor for the walk gate. Its position is
            // reported continuously (below) so reaching the true bottom registers reliably.
            Divider()
                .padding(.vertical, 6)
                .background(GeometryReader { g in
                    Color.clear.preference(key: HeaderPosKey.self,
                                           value: ["F:\(f.monthKey)": g.frame(in: .named("galleryScroll")).minY])
                })
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

// MARK: - Sticky header position tracking

private struct HeaderPosKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Animated coach chevron wave (spec §3)

/// Three amber chevrons that bob in a staggered wave and brighten top→bottom, honoring
/// reduce-motion. Mirrors the Android coach marquee.
private struct ChevronWave: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: -2) {
            ForEach(0..<3) { i in
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.orange.opacity(0.4 + Double(i) * 0.3))
                    .offset(y: animating ? 2 : -2)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.12),
                        value: animating)
            }
        }
        .onAppear { animating = true }
    }
}
