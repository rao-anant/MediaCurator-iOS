import SwiftUI
import Photos

/// Main gallery screen — mirrors Android's `MainActivity` + `GalleryAdapter`.
/// Shows a tree of Year → Month → (Camera / WhatsApp) → thumbnail grid.
struct GalleryView: View {

    @StateObject private var vm = GalleryViewModel()
    var scrollToMonthKey: String? = nil
    /// One-shot sort applied on open (e.g. "Free up space" -> Largest-overall), NOT persisted.
    var initialSort: SortMode? = nil

    @State private var didApplyInitialSort = false
    @State private var selectedItem: MediaItem? = nil
    @State private var showingPermissionAlert = false
    @State private var showingStats = false
    @State private var filterToast: String? = nil
    @State private var showScrollTop = false
    @State private var headerPositions: [String: CGFloat] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    /// Anchor that lands a scroll target just below the sticky header overlay. The sticky bar
    /// floats over the scroll content, so `.top` (y=0) hides the target under it; offsetting by the
    /// bar's fraction of the viewport drops the target into view beneath it.
    /// Land a month header just below the YEAR bar — the only row that stays pinned above it (once
    /// the month header is on screen it unpins itself, by design). Deliberately a CONSTANT, not the
    /// measured bar height: the bar's height now depends on what's pinned, which depends on scroll
    /// position, which this anchor sets — reading it here closed a feedback loop where each nudge
    /// recomputed the anchor from a height the previous nudge had just changed, thrashing the scroll
    /// into nonsense positions (blank screen / a lone year). Mirrors Android's stickyHeaderOffset().
    private var belowStickyAnchor: UnitPoint {
        let h = viewportHeight > 0 ? viewportHeight : 700
        return UnitPoint(x: 0.5, y: min(0.4, (stickyYearRowH + 4) / h))
    }

    /// Only videos are showing — give them bigger tiles (fewer columns). Videos are usually
    /// fewer and read better larger; a 4-wide grid of video thumbnails looks busy. Based on what's
    /// actually displayed (not the include flags, which default to on for PDF/audio even when the
    /// library has none, so those would wrongly keep this false).
    private var videoOnly: Bool {
        !vm.flatMediaItems.isEmpty && vm.flatMediaItems.allSatisfy { $0.type == .video }
    }
    /// Columns in the gallery grid: 3 for a video-only view, 4 otherwise.
    private var columnCount: Int { videoOnly ? 3 : 4 }

    /// Pixel size to request each thumbnail at — the cell's point width (viewport ÷ column count)
    /// times the screen scale. Computed from the stable viewport width so the request key
    /// doesn't change during a month's expand animation (which caused thumbnails to flicker).
    private var cellTargetPx: CGFloat {
        let w = viewportWidth > 0 ? viewportWidth : 400
        return max(240, (w / CGFloat(columnCount)) * displayScale)
    }

    /// Sticky context (spec §3): the year always, the month when scrolled into one. Derived from
    /// the closest header that has scrolled to/above the top. Hidden in flat size-sort mode.
    /// WHICH year the bar is about — model/position derived, and deliberately not gated on
    /// visibility, because `stickyMonthLabel` needs it as a lookup key even when nothing is pinned.
    private var stickyYearCandidate: String? {
        guard vm.sortMode != .sizeAbsolute else { return nil }
        // An open month pins its own year (avoids the strip going blank / wrong for short months).
        if let open = vm.openMonthKey { return String(open.prefix(4)) }
        let ys = headerPositions.filter { $0.key.hasPrefix("Y:") && $0.value <= 0 }
        guard let top = ys.max(by: { $0.value < $1.value }) else { return nil }
        return String(top.key.dropFirst(2))
    }

    /// WHETHER to pin it — same rule the month and sub rows already had, which the year row was
    /// missing (ph8): pin only while the real in-list year row isn't on screen. The open-month
    /// branch above returns a year unconditionally, so with a month open the bar pinned "2024" even
    /// while the real "2024  104  4.2 MB" row sat directly beneath it — the same duplicate-header
    /// bug fixed for months, never applied here. A dropped position means the lazy list discarded
    /// the row (scrolled far away), so pin.
    ///
    /// Gating the whole bar on this is safe: a year header always sits above its own months, so if
    /// it's on screen the open month is below it and needs no stand-in either.
    private var stickyYear: String? {
        guard let year = stickyYearCandidate else { return nil }
        if let y = headerY(prefix: "Y:\(year)"), y > 0 { return nil }
        return year
    }

    /// The model row behind the pinned year, so the bar can carry the same count + size the real
    /// row shows. Android's sticky year row does this (`tvStickyYearStats`); iOS was dropping the
    /// figures the moment the real row scrolled off, which read as the numbers disappearing.
    private func yearHeader(for year: String) -> GalleryItem.YearHeader? {
        guard let y = Int(year) else { return nil }
        for item in vm.galleryItems {
            if case .yearHeader(let h) = item, h.year == y { return h }
        }
        return nil
    }
    /// Approximate heights of the pinned rows — used to tell when a real (in-list) header has slid
    /// behind the bar so its pinned stand-in should take over.
    private let stickyYearRowH: CGFloat = 34
    private let stickyMonthRowH: CGFloat = 46

    /// Reported y of a header, or nil when the LazyVStack has dropped it (i.e. it is far off-screen).
    private func headerY(prefix: String) -> CGFloat? {
        headerPositions.first { $0.key.hasPrefix(prefix) }?.value
    }

    /// Pin the open month ONLY while its real in-list header isn't visible below the year bar —
    /// otherwise "April 2024" shows twice (pinned + in-list). A missing position means the lazy list
    /// dropped the row, i.e. it's scrolled far away, so we pin. (The pre-existing code had this
    /// polarity backwards — absent was read as "no month" and the label vanished mid-month, which is
    /// why it was made unconditional; that caused the duplicate.) Matches Android, whose bar shows
    /// only the year while the real month header is on screen.
    private var showStickyMonth: Bool {
        guard vm.openMonthKey != nil else { return false }
        guard let y = headerY(prefix: "M:\(vm.openMonthKey!)|") else { return true }
        return y <= stickyYearRowH
    }

    /// Same contract for the open sub-group, measured below whatever is pinned above it.
    private var showStickySub: Bool {
        guard let key = vm.openSubGroupKey else { return false }
        let threshold = stickyYearRowH + (showStickyMonth ? stickyMonthRowH : 0)
        guard let y = headerY(prefix: "S:\(key)") else { return true }
        return y <= threshold
    }

    private var stickyMonthLabel: String? {
        guard vm.sortMode != .sizeAbsolute else { return nil }
        if vm.openMonthKey != nil {
            return showStickyMonth ? Formatters.monthLabel(from: vm.openMonthKey!) : nil
        }
        // Candidate, not the gated `stickyYear`: we still need to know which year's months to scan
        // even at a scroll position where the year row itself isn't pinned.
        guard let year = stickyYearCandidate else { return nil }
        let ms = headerPositions.filter { $0.key.hasPrefix("M:\(year)-") && $0.value <= 0 }
        guard let top = ms.max(by: { $0.value < $1.value }) else { return nil }
        return top.key.split(separator: "|").last.map(String.init)
    }

    /// The open sub-group ("Camera & Others" / "WhatsApp"), pinned so its collapse chevron stays
    /// reachable while you scroll its photos. WHICH sub-group is model state (`openSubGroupKey`) —
    /// it must survive the lazy list dropping the row — but WHETHER to pin it is positional, so it
    /// doesn't duplicate the real row while that's on screen.
    private var stickySub: (key: String, label: String)? {
        guard vm.sortMode != .sizeAbsolute, vm.openMonthKey != nil,
              let key = vm.openSubGroupKey, showStickySub else { return nil }
        return (key, vm.openSubGroupLabel)
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
                Color.clear.onAppear {
                    if !UITestHooks.synthetic {
                        Task { await vm.requestAuthorization() }
                    }
                }
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
            // Apply the one-shot open sort exactly once (onAppear re-fires when returning from the
            // viewer; we must not clobber a sort the user changed via the picker meanwhile).
            if let s = initialSort, !didApplyInitialSort {
                didApplyInitialSort = true
                vm.applyInitialSort(s)
            }
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let uiTest = UITestHooks.synthetic
            // Test hook: pretend authorized so the body renders the grid rather than the branch that
            // re-raises the (untappable) permission prompt.
            vm.authorizationStatus = uiTest ? .authorized : status
            if status == .authorized || status == .limited || uiTest {
                vm.loadMedia(forceRefresh: false)
            }
            vm.uiTestDriveIfRequested()
        }
        .fullScreenCover(item: $selectedItem) { item in
            // Gallery: page only within the opened photo's month (spec / Android behavior) — EXCEPT
            // in flat "Largest files" sort, which isn't grouped by month. There, month-scoping would
            // trap paging/deletion inside one month while the next-largest items sit in other months
            // (looked "stuck"); page the whole flat list instead.
            MediaViewerView(vm: vm, startingID: item.id, monthScoped: vm.sortMode != .sizeAbsolute)
        }
    }

    // MARK: - Sticky header (spec §3)

    @ViewBuilder
    private var stickyHeader: some View {
        if let year = stickyYear, !vm.selectionMode {
            VStack(spacing: 0) {
                // Each pinned row collapses ITS OWN level (matches Android's 3-row sticky header):
                // year -> all-years list, month -> that year's month list, sub-group -> that month's
                // Camera & Others + WhatsApp. Tapping the deepest row is therefore "up one level".
                Button {
                    if let y = Int(year) { vm.toggleYearExpansion(y) }
                } label: {
                    HStack(spacing: 8) {
                        // Left-side chevron.down matches the in-list tree rows (and Android). It's an
                        // expanded node you tap to collapse — just pinned here so it stays reachable
                        // when the real header has scrolled far off the top.
                        Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(year).font(.subheadline).bold()
                        Spacer()
                        // Same figures as the real row, so scrolling doesn't make them vanish
                        // (matches Android's tvStickyYearStats). One line, not the real row's
                        // stacked pair, to keep the pinned bar slim.
                        if let h = yearHeader(for: year) {
                            Text("\(Formatters.countShort(h.totalItems)) · \(Formatters.bytes(h.totalBytes))")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    // Fully opaque: at 0.96 the real row bled a faint ghost of its counts through
                    // the bar as it scrolled underneath.
                    .background(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                if let month = stickyMonthLabel {
                    Button {
                        // Collapse the open month if this sticky month is it.
                        if let key = vm.openMonthKey { vm.toggleMonthExpansion(key) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
                                .frame(width: 16)
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
                        .background(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }
                // Third row: the open sub-group, pinned so its collapse chevron stays reachable
                // while scrolling its photos. Tapping shows that month's Camera & Others + WhatsApp.
                if let sub = stickySub {
                    Button {
                        vm.toggleSubGroupExpansion(sub.key)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.tertiary)
                                .frame(width: 16)
                            Text(sub.label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 24).padding(.vertical, 4)
                        .background(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
        }
    }

    // MARK: - Sort bar

    /// Slim "jump back" pill (design debate Topic 1): appears once a second month is opened, always
    /// Always-visible sort indicator at the top of the gallery — shows the current order
    /// and lets the user change it (mirrors Android's gallery sort header). Trailing it, in the
    /// same status row, is the read-only previous-explored-month label (see `previousMonthLabel`).
    private var sortBar: some View {
        VStack(spacing: 0) {
            // One row when both fit; otherwise the label drops to its own line. The long sort
            // names ("Most items per month") leave too little room beside them on a narrow phone,
            // and truncating gave "Came from…" — hiding the month, the only thing the label is
            // there to say. Better to spend a line than to say nothing.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    sortMenu
                    Spacer(minLength: 8)
                    previousMonthText
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) { sortMenu; Spacer(minLength: 0) }
                    previousMonthText
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            Divider()
        }
    }

    private var sortMenu: some View {
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
                    .fontWeight(.medium).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    /// Previous-explored-month, phase 1: plain secondary text, NO arrow / pill / tint — an
    /// affordance on non-interactive text invites a tap that does nothing. Hit testing is off so
    /// it can't steal the sort menu's tap either.
    @ViewBuilder
    private var previousMonthText: some View {
        if let prev = vm.previousMonthLabel {
            Text("Came from \(prev)")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1)
                .allowsHitTesting(false)
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

    private var gridColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount) }

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
                if let key { withAnimation { proxy.scrollTo("month-\(key)", anchor: belowStickyAnchor) } }
            }
            .onChange(of: vm.scrollRequest) { req in
                // Opening a year / month / sub-group lands it at the top (§3 Landing, G-5/G-6).
                // The list is mid-relayout (the accordion collapses other months while the tapped
                // level's rows appear), so a single early scroll can miss the target's final
                // position. Nudge it a few times across the settle window — once the target is at
                // the top the later calls are no-ops, so it lands reliably without visible jank.
                guard let req else { return }
                let anchor: UnitPoint = req.belowSticky ? belowStickyAnchor : .top
                // Nudge across the settle window (the accordion collapses other months and the grid
                // lays out after the first tick). The anchor is constant, so these converge instead
                // of chasing a bar height they themselves change.
                for delay in [0.05, 0.2, 0.4, 0.65] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(req.id, anchor: anchor) }
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
                // Only an EXPANDED sub-group reports: it's the one that can be pinned, and its
                // absence (lazy list dropped it) is what tells us to pin. See `showStickySub`.
                .background(GeometryReader { g in
                    Color.clear.preference(
                        key: HeaderPosKey.self,
                        value: s.isExpanded
                            ? ["S:\(s.subKey)": g.frame(in: .named("galleryScroll")).minY]
                            : [:])
                })
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
