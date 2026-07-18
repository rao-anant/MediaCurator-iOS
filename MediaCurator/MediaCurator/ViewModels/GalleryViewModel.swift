import Foundation
import Photos
import Combine

/// Owns the gallery item list, sort/filter state, deletion, and undo.
/// Mirrors Android's `GalleryViewModel`.
@MainActor
final class GalleryViewModel: ObservableObject {

    // MARK: - Published state

    @Published var galleryItems: [GalleryItem] = []
    @Published var flatMediaItems: [MediaItem] = []   // all visible items, expansion-independent
    @Published var isLoading = false
    @Published var sortMode: SortMode
    @Published var includePhoto: Bool
    @Published var includeVideo: Bool
    @Published var includePdf: Bool
    @Published var includeAudio: Bool
    @Published var mediaStats: MediaStats = .empty
    @Published var lastBatchSize: Int = 0
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    // MARK: - Selection mode

    @Published var selectionMode = false
    @Published var selectedIDs: Set<String> = []

    var selectedItems: [MediaItem] { flatMediaItems.filter { selectedIDs.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func enterSelection(_ id: String) {
        selectionMode = true
        selectedIDs = [id]
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    func exitSelection() {
        selectionMode = false
        selectedIDs = []
    }

    func deleteSelected() {
        let items = selectedItems
        exitSelection()
        requestDelete(items)
    }

    func shareSelected() {
        shareItems(selectedItems)
    }

    /// Non-nil while an undo window is open after a delete. Drives the undo toast.
    @Published var pendingUndo: PendingUndo? = nil

    struct PendingUndo: Equatable {
        let message: String
        let count: Int
    }

    /// Non-nil briefly after a month is marked done. Drives the "marked done" undo toast.
    @Published var doneToast: DoneToast? = nil

    struct DoneToast: Equatable {
        let monthKey: String
        let label: String
    }

    private var doneToastTask: Task<Void, Never>? = nil

    /// Seconds the "Moved to Trash" toast stays up. Purely cosmetic — the item stays staged
    /// (and hidden) after it dismisses; nothing is committed to Photos here.
    private let toastSeconds: UInt64 = 4
    private var undoToastTask: Task<Void, Never>? = nil

    // MARK: - Private

    let prefs: PreferencesManager
    private let repo: MediaRepository
    private let trashManager: TrashManager

    /// Items deleted this session — never cleared while app is running.
    /// Guards against MediaStore-equivalent lag where deleted items briefly reappear.
    private var sessionDeletedIDs: Set<String> = []

    /// Items staged for deletion (app-managed trash): hidden in our app but still in the
    /// Photos library until the user commits the batch from the Trash screen. Persisted.
    private var stagedIDs: Set<String> = []
    /// The most recent stage action, so the toast's Undo can un-stage exactly those.
    private var lastStagedBatch: [MediaItem] = []

    private var structuralVersion = 0
    private var expandedYears:     Set<Int>    = []
    private var expandedMonths:    Set<String> = []
    private var expandedSubGroups: Set<String> = []
    /// Per-(month,sub,type) "seen" keys (persisted, grows only) — gates the "Hide Month"
    /// button. e.g. "2024-03:cam:video".
    private var seenSubGroups:     Set<String> = []
    /// Full type presence per "<month>:<sub>" ignoring the chip filter (recomputed each load).
    private var monthTypePresence: [String: Set<MediaType>] = [:]
    /// Full item count per month (chip-independent) — for the revisit shortcut.
    private var monthItemCounts: [String: Int] = [:]

    private var loadTask: Task<Void, Never>? = nil
    private var photoLibraryObserver: PhotoLibraryObserver? = nil

    // MARK: - Init

    init(
        prefs: PreferencesManager = PreferencesManager(),
        repo: MediaRepository = MediaRepository(),
        trashManager: TrashManager = .shared
    ) {
        self.prefs        = prefs
        self.repo         = repo
        self.trashManager = trashManager

        self.sortMode     = prefs.getSortMode()
        self.includePhoto = prefs.isIncludePhoto()
        self.includeVideo = prefs.isIncludeVideo()
        self.includePdf   = prefs.isIncludePdf()
        self.includeAudio = prefs.isIncludeAudio()

        self.expandedYears     = prefs.getExpandedYears()
        // Accordion: at most one open month. Collapse any legacy multi-expanded state.
        let savedMonths = prefs.getExpandedMonths()
        self.openMonthKey      = savedMonths.first
        self.expandedMonths    = savedMonths.isEmpty ? [] : [savedMonths.first!]
        self.expandedSubGroups = prefs.getExpandedSubGroups()
        self.seenSubGroups     = prefs.getSeenSubGroups()
        self.stagedIDs         = prefs.getStagedForDeletion()
        self.scrollHintRetired = prefs.isScrollHintRetired()
        self.walkedCounts      = prefs.getWalkedCounts()

        self.lastBatchSize = prefs.getLastDeletedBatch().count

        // Observe Photos library changes (mirrors Android's ContentObserver). Registering accesses
        // the library, which raises the permission prompt on .notDetermined — skip under the
        // screenshot-test flag (which uses synthetic data and never touches PhotoKit).
        if !UITestHooks.synthetic {
            photoLibraryObserver = PhotoLibraryObserver { [weak self] in
                Task { @MainActor [weak self] in self?.loadMedia(forceRefresh: true) }
            }
            PHPhotoLibrary.shared().register(photoLibraryObserver!)
        }
    }

    deinit {
        if let obs = photoLibraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(obs)
        }
    }

    /// Seed the viewer's flat list from an external screen (e.g. Place browse) so it can page a
    /// plain item list without the full gallery tree.
    func seedViewer(items: [MediaItem]) { flatMediaItems = items }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        if status == .authorized || status == .limited {
            loadMedia(forceRefresh: false)
        }
    }

    // MARK: - Load

    func loadMedia(forceRefresh: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            await performLoad(forceRefresh: forceRefresh)
        }
    }

    private func performLoad(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }

        DebugLog.i("gallery", "load start forceRefresh=\(forceRefresh)")
        let allMedia = await MediaCache.shared.get(repo: repo, forceRefresh: forceRefresh)

        // Re-read staged set from prefs (picks up restores made on the Trash screen) and
        // reconcile it against the library — drop any staged id that no longer resolves to
        // an asset (e.g. the user deleted it directly in the Photos app).
        let liveIDs = Set(allMedia.map(\.id))
        stagedIDs = prefs.getStagedForDeletion().intersection(liveIDs)
        prefs.setStagedForDeletion(stagedIDs)

        // Hide committed session-deletes and items staged for deletion.
        let filtered = allMedia.filter {
            !sessionDeletedIDs.contains($0.id) && !stagedIDs.contains($0.id)
        }

        // Full type presence per (month, sub-group), IGNORING the chip filter — the
        // "Hide Month" gate needs to know every type that exists so a disabled chip can't
        // sneak the button on. Keyed "<month>:<sub>" → set of types present.
        var presence: [String: Set<MediaType>] = [:]
        var itemCounts: [String: Int] = [:]
        let cal = Calendar.current
        for item in filtered {
            let y = cal.component(.year, from: item.dateTaken)
            let m = cal.component(.month, from: item.dateTaken)
            let monthKey = PreferencesManager.monthKey(year: y, month: m)
            presence["\(monthKey):\(item.isWhatsApp ? "wa" : "cam")", default: []].insert(item.type)
            itemCounts[monthKey, default: 0] += 1
        }
        monthTypePresence = presence
        monthItemCounts = itemCounts

        // Apply type filters
        let typeFiltered = filtered.filter { item in
            switch item.type {
            case .image: return includePhoto
            case .video: return includeVideo
            case .pdf:   return includePdf
            case .audio: return includeAudio
            }
        }

        let (visible, done) = repo.processAndGroupMedia(typeFiltered)
        visibleMonthKeys = Set(visible.map(\.key))   // drives the previous-month pill's validity
        let built = buildGalleryItems(visible: visible, done: done, allMedia: typeFiltered)

        galleryItems   = built.items
        flatMediaItems = built.flat
        mediaStats     = computeStats(all: allMedia, done: done)

        // Open-month metrics for the pinned Hide bar + walk gate.
        if let open = openMonthKey {
            openMonthItemCount     = monthItemCounts[open] ?? 0
            openMonthRenderedLength = built.items.filter { $0.monthKey == open }.count
            // Count + size for the sticky header — taken from the month's own Header so it matches
            // the month-row exactly.
            if let h = built.items.lazy.compactMap({ item -> GalleryItem.Header? in
                if case .header(let hh) = item, hh.monthKey == open { return hh } else { return nil }
            }).first {
                openMonthCount = h.count
                openMonthBytes = h.totalBytes
            } else {
                openMonthCount = openMonthItemCount
                openMonthBytes = 0
            }
        } else {
            openMonthItemCount = 0
            openMonthRenderedLength = 0
            openMonthCount = 0
            openMonthBytes = 0
        }
        recomputeHideBar()

        DebugLog.i("gallery", "load done items=\(galleryItems.count)")
    }

    // MARK: - Deletion (stage to app-managed trash)

    /// Stage [items] for deletion: hide them in the app and persist the staged set. Nothing
    /// is committed to Photos here — the user reviews and commits the batch on the Trash
    /// screen. A short toast offers an immediate Undo (un-stage).
    func requestDelete(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        for item in items { stagedIDs.insert(item.id) }
        prefs.setStagedForDeletion(stagedIDs)
        lastStagedBatch = items

        pendingUndo = PendingUndo(
            message: items.count == 1 ? "Moved to Trash" : "\(items.count) moved to Trash",
            count: items.count
        )
        loadMedia(forceRefresh: false)   // re-filter from cache (cheap), hides the items

        // Auto-dismiss the toast; the item stays staged (and hidden) regardless.
        undoToastTask?.cancel()
        undoToastTask = Task { [toastSeconds] in
            try? await Task.sleep(nanoseconds: toastSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            pendingUndo = nil
        }
    }

    /// Un-stage the most recent batch (the toast's Undo).
    func undoDelete() {
        undoToastTask?.cancel()
        for item in lastStagedBatch { stagedIDs.remove(item.id) }
        prefs.setStagedForDeletion(stagedIDs)
        lastStagedBatch = []
        pendingUndo = nil
        loadMedia(forceRefresh: false)
    }

    // MARK: - Done months

    func markMonthDone(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        prefs.markMonthDone(year: y, month: m)
        // A hidden month has left the list — a jump-back to it would be a dead link (design
        // debate Topic 1, point 6). Clear the pointer if it was aimed there.
        if previousMonthKey == key { previousMonthKey = nil }
        structuralVersion += 1
        // Marking done is instantly reversible (just a prefs flag), so no deferred commit —
        // we surface an Undo toast purely as a convenience / confirmation.
        showDoneToast(key: key)
        loadMedia(forceRefresh: false)
    }

    func unmarkMonthDone(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        prefs.unmarkMonthDone(year: y, month: m)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    /// Undo the most recently marked-done month (driven by the toast).
    func undoMarkDone() {
        guard let toast = doneToast else { return }
        doneToastTask?.cancel()
        doneToast = nil
        unmarkMonthDone(key: toast.monthKey)
    }

    private func showDoneToast(key: String) {
        doneToastTask?.cancel()
        doneToast = DoneToast(monthKey: key, label: Formatters.monthLabel(from: key))
        doneToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.doneToast = nil
        }
    }

    // MARK: - Sort

    /// Apply a sort on open WITHOUT persisting it as the user's default (e.g. "Free up space" ->
    /// Largest-overall). A later fresh gallery visit reverts to the saved sort. No reload here —
    /// the caller's onAppear loadMedia runs right after and picks up the new sortMode.
    func applyInitialSort(_ mode: SortMode) {
        guard mode != sortMode else { return }
        sortMode = mode
        structuralVersion += 1
    }

    func setSortMode(_ mode: SortMode) {
        guard mode != sortMode else { return }
        sortMode = mode
        prefs.saveSortMode(mode)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    // MARK: - Expand / Collapse

    func toggleYearExpansion(_ year: Int) {
        if expandedYears.contains(year) {
            expandedYears.remove(year)
            // Collapsing a year closes any open month inside it — otherwise the sticky bar and the
            // "Hide {month}" bar kept showing that now-hidden month while the list was elsewhere (ph4).
            if let open = openMonthKey, open.hasPrefix(String(year)) {
                openMonthKey = nil
                openSubGroupKey = nil
                expandedMonths.remove(open)
                hideBarState = .none
            }
            // Keep the just-closed year in view instead of letting it drift above the top (ph4).
            requestScroll(toID: "year-\(year)")
        }
        else {
            expandedYears.insert(year)
            requestScroll(toID: "year-\(year)")   // land the opened year at the very top (§3)
        }
        prefs.saveExpandedYears(expandedYears)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    /// The single month currently open in the accordion (nil = none). Drives the pinned bar.
    @Published var openMonthKey: String? = nil

    // MARK: - Previous-explored-month indicator (design debate Topic 1)

    /// The month open immediately before the current one. Single slot, no stack; session-only.
    /// Set when a different month is opened; cleared when it leaves the visible list (hidden /
    /// filtered out). Drives the "jump back" pill.
    @Published var previousMonthKey: String? = nil
    /// Month keys currently in the visible gallery (post hide-split + type-filter). Used to drop the
    /// pointer when its target is no longer reachable.
    private var visibleMonthKeys: Set<String> = []
    /// The pill's label, or nil when it should be hidden: needs a previous month, an open current
    /// month to be "previous" to, and the target still present in the visible list.
    var previousMonthLabel: String? {
        guard let prev = previousMonthKey, openMonthKey != nil,
              prev != openMonthKey, visibleMonthKeys.contains(prev) else { return nil }
        return Formatters.monthLabel(from: prev)
    }
    /// Tap the pill: re-open the previous month. The month we leave becomes the new "previous",
    /// producing an A/B bounce between the two most-recent months.
    func jumpToPreviousMonth() {
        guard let prev = previousMonthKey, prev != openMonthKey,
              visibleMonthKeys.contains(prev) else { return }
        toggleMonthExpansion(prev)
    }

    /// The sub-group currently open inside `openMonthKey` (most recently expanded if both are).
    /// Drives the pinned sub-group row. Derived from the MODEL, never from on-screen header
    /// positions: the sub-header lives in a LazyVStack, so scrolling into its photos drops the row
    /// and any position-derived value would vanish exactly when the pin is needed most.
    @Published var openSubGroupKey: String? = nil
    /// Display label for `openSubGroupKey` — the key suffix decides it (":wa" vs ":cam").
    var openSubGroupLabel: String {
        guard let k = openSubGroupKey else { return "" }
        return k.hasSuffix(":wa") ? "WhatsApp" : "Camera & Others"
    }
    /// Display metrics for the open month, shown in the sticky header (year › month › "N photos · size").
    @Published var openMonthCount = 0
    @Published var openMonthBytes: Int64 = 0

    // MARK: - Pinned Hide-month bar (spec §3 / CURATION_REGRESSION_TESTS)

    @Published var hideBarState: HideBarState = .none
    @Published var hideBarMonthLabel = ""
    @Published var hideBarHintText = ""

    /// A request to scroll a just-expanded row to the top (spec §3 Landing / G-5, G-6).
    /// The token makes re-expanding the same row retrigger the onChange.
    /// `belowSticky` = land the target just under the floating sticky bar (used only when opening a
    /// month, so its sub-header + first row clear the bar). For collapses and year-open we land at
    /// the true top instead, so the sticky bar shows the row the user acted on — not the one above it.
    struct ScrollRequest: Equatable { let id: String; let token: UUID; let belowSticky: Bool }
    @Published var scrollRequest: ScrollRequest? = nil
    private func requestScroll(toID id: String, belowSticky: Bool = false) {
        scrollRequest = ScrollRequest(id: id, token: UUID(), belowSticky: belowSticky)
    }

    private var uiTestDriven = false
    /// Screenshot-test hook (only runs with the `-uiGalleryScroll` launch arg, never in normal use):
    /// drives the accordion to "April 2024 > Camera open, scrolled to the bottom" so the sticky-header
    /// rendering at a deep scroll position can be captured on a machine that can't tap the simulator.
    func uiTestDriveIfRequested() {
        guard UITestHooks.galleryScroll || UITestHooks.prevMonth, !uiTestDriven else { return }
        uiTestDriven = true

        // prevMonth: open one month, then a second one, so the first becomes "previous" and the
        // jump-back pill appears naming it (design debate Topic 1). Verifies the pill's layout.
        if UITestHooks.prevMonth {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !expandedYears.contains(2024) { toggleYearExpansion(2024) }
                try? await Task.sleep(nanoseconds: 700_000_000)
                toggleMonthExpansion("2024-02")   // open February first
                try? await Task.sleep(nanoseconds: 700_000_000)
                toggleMonthExpansion("2024-04")   // then April → previous = February 2024
            }
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !expandedYears.contains(2024) { toggleYearExpansion(2024) }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !expandedMonths.contains("2024-04") { toggleMonthExpansion("2024-04") }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !expandedSubGroups.contains("2024-04:cam") { toggleSubGroupExpansion("2024-04:cam") }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // Scroll to the WhatsApp sub-header, which sits below all 40 camera tiles: pushes the
            // real "April 2024" header off the top so the sticky bar engages (the bug scenario).
            requestScroll(toID: "sub-2024-04:wa", belowSticky: true)

            // p2 repro: collapse April from the scrolled-down position and see where it lands.
            if UITestHooks.collapseAfterScroll {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                toggleMonthExpansion("2024-04")   // collapse the open, scrolled month
            }
        }
    }

    private var walk = WalkLatch()
    private var scrollHintRetired = false
    private var walkedCounts: [String: Int] = [:]
    /// The open month's full item count (chip-independent) and rendered row count.
    private var openMonthItemCount = 0
    private var openMonthRenderedLength = 0

    func toggleMonthExpansion(_ key: String) {
        if expandedMonths.contains(key) {
            expandedMonths.remove(key)
            openMonthKey = nil
            openSubGroupKey = nil
            hideBarState = .none
            // Keep the month the user just closed in view — collapsing removed its photos, which
            // otherwise let the header drift above the top of the screen (see ph4).
            requestScroll(toID: "month-\(key)")
        } else {
            // The month we're leaving becomes "previous" — drives the jump-back pill (design
            // debate Topic 1). "The month you left, however you left it."
            if let leaving = openMonthKey, leaving != key { previousMonthKey = leaving }
            // Accordion: only one month open at a time. Opening a month collapses the
            // previously open month and all sub-group expansions (spec §3).
            expandedMonths = [key]
            expandedSubGroups.removeAll()
            openSubGroupKey = nil
            openMonthKey = key
            walk.opened(key)   // begin a fresh walk (nothing seen yet)
            prefs.setLastViewedMonth(key)   // "pick up where you left off" resume target
            prefs.saveExpandedSubGroups(expandedSubGroups)
            // Opening a month: land it below the sticky bar so its sub-header + first row are visible.
            requestScroll(toID: "month-\(key)", belowSticky: true)
        }
        prefs.saveExpandedMonths(expandedMonths)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    /// Fed by the gallery when the open month's header/footer visibility changes (settled list).
    func evaluateWalk(headerVisible: Bool, footerVisible: Bool) {
        guard let open = openMonthKey else { return }
        walk.viewportEvaluated(openMonth: open, headerVisible: headerVisible,
                               footerVisible: footerVisible, renderedLength: openMonthRenderedLength)
        if walk.isReached(open) {
            walkedCounts[open] = openMonthItemCount
            prefs.setWalkedCount(month: open, count: openMonthItemCount)
        }
        recomputeHideBar()
    }

    /// Tap on the pinned "Hide {Month}" bar. (Hiding does NOT retire the coach hints — they keep
    /// helping on later months until the user actively dismisses them with the ✕.)
    func hideOpenMonth() {
        guard let open = openMonthKey else { return }
        walkedCounts[open] = openMonthItemCount
        prefs.setWalkedCount(month: open, count: openMonthItemCount)
        openMonthKey = nil
        hideBarState = .none
        markMonthDone(key: open)   // hides + shows the undo toast + rebuilds
        // The hidden month's rows are gone, so the list is now shorter. Without this the
        // ScrollView stays parked where the user was (deep in that month) — past the end of the
        // new content — showing a blank screen. Snap to the top so the remaining months appear.
        requestScroll(toID: "gallery-top")
    }

    /// Dismiss (✕) a coach hint — the ONLY thing that retires future coaching.
    func dismissHideHint() {
        retireHints()
        recomputeHideBar()
    }

    private func retireHints() {
        scrollHintRetired = true
        prefs.setScrollHintRetired()
    }

    private func recomputeHideBar() {
        guard let open = openMonthKey else { hideBarState = .none; return }
        let reviewed = monthFullyReviewed(open)
        let revisit = walkedCounts[open].map {
            WalkedMonthRule.stillWalked(walkedCount: $0, currentCount: openMonthItemCount)
        } ?? false
        let reached = walk.isReached(open) || revisit
        let hint = reviewHintText(open)
        let state = HideBarDecision.decide(showHideButton: reviewed,
                                           reachedEnd: reached,
                                           scrollHintRetired: scrollHintRetired,
                                           hasReviewHint: !reviewed && hint != nil)
        hideBarState = state
        hideBarMonthLabel = Formatters.monthLabel(from: open)
        switch state {
        case .reviewHint:   hideBarHintText = hint ?? ""
        case .scrollTeaser: hideBarHintText = "Delete junk as you scroll — hide \(hideBarMonthLabel) at the end"
        case .hide, .none:  hideBarHintText = ""
        }
    }

    /// Text nudging the user toward the still-unreviewed part of the open month, or nil if done.
    private func reviewHintText(_ month: String) -> String? {
        if monthFullyReviewed(month) { return nil }
        let label = Formatters.monthLabel(from: month)
        let camTypes = monthTypePresence["\(month):cam"] ?? []
        let waTypes  = monthTypePresence["\(month):wa"]  ?? []
        // A present type with its chip off → the user can't review it until they enable it.
        let allPresent = camTypes.union(waTypes)
        if allPresent.contains(where: { !isChipOn($0) }) {
            return "Turn on all type filters to review \(label)"
        }
        let camSeen = subgroupFullySeen(month, "cam")
        let waSeen  = subgroupFullySeen(month, "wa")
        let camPresent = !camTypes.isEmpty
        let waPresent  = !waTypes.isEmpty
        if camPresent && waPresent && !camSeen && !waSeen { return "Open both sections to review \(label)" }
        if waPresent && !waSeen  { return "Also open WhatsApp to review \(label)" }
        if camPresent && !camSeen { return "Also open Camera & Others to review \(label)" }
        return "Open \(label) to review it"
    }

    private func subgroupFullySeen(_ month: String, _ sub: String) -> Bool {
        let types = monthTypePresence["\(month):\(sub)"] ?? []
        return types.allSatisfy { seenSubGroups.contains("\(month):\(sub):\($0.rawValue)") }
    }

    private func isChipOn(_ type: MediaType) -> Bool {
        switch type {
        case .image: return includePhoto
        case .video: return includeVideo
        case .pdf:   return includePdf
        case .audio: return includeAudio
        }
    }

    func toggleSubGroupExpansion(_ key: String) {
        if expandedSubGroups.contains(key) {
            expandedSubGroups.remove(key)
            if openSubGroupKey == key { openSubGroupKey = expandedSubGroups.first }
            // Collapsing removes every photo the user scrolled past, so without an anchor the list
            // loses its position and dumps them on an unrelated month (the bug Android hit in a33
            // when collapsing from its sticky bar). Land on the parent month so they see that
            // month's sub-group list — Camera & Others + WhatsApp.
            let parentMonth = String(key.prefix(while: { $0 != ":" }))
            requestScroll(toID: "month-\(parentMonth)", belowSticky: true)
        }
        else {
            expandedSubGroups.insert(key)
            openSubGroupKey = key   // pins this sub-group's collapse chevron in the sticky bar
            // Mark as "seen" per currently-enabled type: a type counts as reviewed only when
            // the sub-group is opened while that type's filter chip is on. Keys are
            // "<month>:<sub>:<type>", e.g. "2024-03:cam:video". Persisted, grows only.
            var changed = false
            for type in enabledTypes where seenSubGroups.insert("\(key):\(type.rawValue)").inserted {
                changed = true
            }
            if changed { prefs.saveSeenSubGroups(seenSubGroups) }
            // G-6: opening a sub-group scrolls its PARENT MONTH to the top, so the sibling
            // (unopened) sub-group line stays visible under the month header. Key is
            // "<month>:<sub>" → parent month is the part before ":".
            let parentMonth = String(key.prefix(while: { $0 != ":" }))
            requestScroll(toID: "month-\(parentMonth)")
        }
        prefs.saveExpandedSubGroups(expandedSubGroups)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    /// True when every (sub-group, type) that exists in the month has been reviewed — each
    /// type seen with its chip on, in whichever sub-group(s) contain it. Gates "Hide Month".
    private func monthFullyReviewed(_ monthKey: String) -> Bool {
        for sub in ["cam", "wa"] {
            let types = monthTypePresence["\(monthKey):\(sub)"] ?? []
            for type in types where !seenSubGroups.contains("\(monthKey):\(sub):\(type.rawValue)") {
                return false
            }
        }
        return true
    }

    /// Media types whose filter chip is currently enabled.
    private var enabledTypes: [MediaType] {
        var t: [MediaType] = []
        if includePhoto { t.append(.image) }
        if includeVideo { t.append(.video) }
        if includeAudio { t.append(.audio) }
        if includePdf   { t.append(.pdf) }
        return t
    }

    // MARK: - Type filters

    /// Toggle a type filter, enforcing the "at least one filter must stay active" floor (spec §3).
    /// Returns false if the toggle was rejected (would have turned off the last active filter).
    @discardableResult
    func toggleTypeFilter(_ type: MediaType) -> Bool {
        let isOn: Bool
        switch type {
        case .image: isOn = includePhoto
        case .video: isOn = includeVideo
        case .pdf:   isOn = includePdf
        case .audio: isOn = includeAudio
        }
        // Count active filters only among types that actually exist in the library — a
        // type with no items (e.g. PDF/audio in v1) must not count toward the floor, or the
        // user could disable every visible chip.
        let activeAndPresent = [
            (includePhoto, mediaStats.totalPhotos),
            (includeVideo, mediaStats.totalVideos),
            (includePdf,   mediaStats.totalPdfs),
            (includeAudio, mediaStats.totalAudios),
        ].filter { $0.0 && $0.1 > 0 }.count
        if isOn && activeAndPresent <= 1 { return false }   // can't disable the last visible filter

        switch type {
        case .image: setIncludePhoto(!includePhoto)
        case .video: setIncludeVideo(!includeVideo)
        case .pdf:   setIncludePdf(!includePdf)
        case .audio: setIncludeAudio(!includeAudio)
        }
        return true
    }

    func setIncludePhoto(_ v: Bool) {
        guard includePhoto != v else { return }
        includePhoto = v; prefs.saveIncludePhoto(v)
        loadMedia(forceRefresh: false)
    }
    func setIncludeVideo(_ v: Bool) {
        guard includeVideo != v else { return }
        includeVideo = v; prefs.saveIncludeVideo(v)
        loadMedia(forceRefresh: false)
    }
    func setIncludePdf(_ v: Bool) {
        guard includePdf != v else { return }
        includePdf = v; prefs.saveIncludePdf(v)
        loadMedia(forceRefresh: false)
    }
    func setIncludeAudio(_ v: Bool) {
        guard includeAudio != v else { return }
        includeAudio = v; prefs.saveIncludeAudio(v)
        loadMedia(forceRefresh: false)
    }

    // MARK: - Gallery item builder

    private struct BuiltGallery {
        var items: [GalleryItem]
        var flat: [MediaItem]
    }

    private func buildGalleryItems(
        visible: [MonthGroup],
        done: [MonthGroup],
        allMedia: [MediaItem]
    ) -> BuiltGallery {
        var items: [GalleryItem] = []
        var flat:  [MediaItem]  = []
        let sv = structuralVersion

        if sortMode == .sizeAbsolute {
            // Flat mode: all items sorted by size descending, no tree headers
            let sorted = allMedia.sorted { $0.size > $1.size }
            for (idx, item) in sorted.enumerated() {
                let label = Formatters.monthLabel(from: PreferencesManager.monthKey(
                    year: Calendar.current.component(.year, from: item.dateTaken),
                    month: Calendar.current.component(.month, from: item.dateTaken)
                ))
                items.append(.media(.init(
                    mediaItem: item,
                    monthKey: "",
                    indexInMonth: idx,
                    dateLabel: label,
                    structuralVersion: sv
                )))
                flat.append(item)
            }
            return BuiltGallery(items: items, flat: flat)
        }

        // Tree mode: year → month → (cam subgroup / wa subgroup) → items.
        // Date direction: oldest-first ascends years/months; everything else descends.
        let ascending = (sortMode == .dateOldest)
        // Group visible months by year
        var byYear: [Int: [MonthGroup]] = [:]
        for mg in visible {
            byYear[mg.year, default: []].append(mg)
        }
        let years = byYear.keys.sorted(by: ascending ? (<) : (>))

        for year in years {
            let monthGroups = byYear[year]!
            let yearItems   = monthGroups.flatMap { $0.items }
            let yearExpanded = expandedYears.contains(year)

            let doneInYear = done.filter { $0.year == year }
            let totalMonthsInYear = monthGroups.count + doneInYear.count
            let doneCount = doneInYear.count
            let curatedPct = totalMonthsInYear > 0 ? doneCount * 100 / totalMonthsInYear : 0

            items.append(.yearHeader(.init(
                year: year,
                totalItems: yearItems.count,
                totalBytes: yearItems.reduce(0) { $0 + $1.size },
                isExpanded: yearExpanded,
                photoCount: yearItems.filter { $0.type == .image }.count,
                videoCount: yearItems.filter { $0.type == .video }.count,
                pdfCount:   yearItems.filter { $0.type == .pdf }.count,
                audioCount: yearItems.filter { $0.type == .audio }.count,
                previewIdentifiers: Array(yearItems.prefix(4).map { $0.localIdentifier }),
                curatedPct: curatedPct,
                structuralVersion: sv
            )))

            guard yearExpanded else { continue }

            for mg in monthGroups.sorted(by: { ascending ? $0.key < $1.key : $0.key > $1.key }) {
                let monthExpanded = expandedMonths.contains(mg.key)

                items.append(.header(.init(
                    monthKey: mg.key,
                    label: mg.label,
                    count: mg.items.count,
                    totalBytes: mg.items.reduce(0) { $0 + $1.size },
                    isExpanded: monthExpanded,
                    photoCount: mg.items.filter { $0.type == .image }.count,
                    videoCount: mg.items.filter { $0.type == .video }.count,
                    pdfCount:   mg.items.filter { $0.type == .pdf }.count,
                    audioCount: mg.items.filter { $0.type == .audio }.count,
                    structuralVersion: sv
                )))

                guard monthExpanded else { continue }

                // Split into Camera & Others vs WhatsApp sub-groups, each ordered by
                // the same date direction as the tree.
                let byDate: (MediaItem, MediaItem) -> Bool = {
                    ascending ? $0.dateTaken < $1.dateTaken : $0.dateTaken > $1.dateTaken
                }
                let waItems  = mg.items.filter { $0.isWhatsApp }.sorted(by: byDate)
                let camItems = mg.items.filter { !$0.isWhatsApp }.sorted(by: byDate)

                for (subLabel, subKey, subItems) in [
                    ("Camera & Others", "\(mg.key):cam", camItems),
                    ("WhatsApp",        "\(mg.key):wa",  waItems)
                ] {
                    guard !subItems.isEmpty else { continue }
                    let subExpanded = expandedSubGroups.contains(subKey)

                    items.append(.subHeader(.init(
                        subKey: subKey,
                        monthKey: mg.key,
                        label: subLabel,
                        count: subItems.count,
                        totalBytes: subItems.reduce(0) { $0 + $1.size },
                        isExpanded: subExpanded,
                        photoCount: subItems.filter { $0.type == .image }.count,
                        videoCount: subItems.filter { $0.type == .video }.count,
                        pdfCount:   subItems.filter { $0.type == .pdf }.count,
                        audioCount: subItems.filter { $0.type == .audio }.count,
                        structuralVersion: sv
                    )))

                    if subExpanded {
                        for (idx, item) in subItems.enumerated() {
                            items.append(.media(.init(
                                mediaItem: item,
                                monthKey: mg.key,
                                indexInMonth: idx,
                                dateLabel: nil,
                                structuralVersion: sv
                            )))
                        }
                    }
                }
                // Footer is the month's bottom anchor for the walk gate (a thin divider now;
                // the Hide action moved to the pinned bar). Always render it for the open month.
                items.append(.footer(.init(monthKey: mg.key, structuralVersion: sv)))
            }
        }

        // The viewer pages through ALL visible items regardless of which groups are
        // expanded in the tree, so build `flat` independently in display order
        // (year desc → month desc → Camera & Others, then WhatsApp).
        let byDate: (MediaItem, MediaItem) -> Bool = {
            ascending ? $0.dateTaken < $1.dateTaken : $0.dateTaken > $1.dateTaken
        }
        for year in years {
            for mg in byYear[year]!.sorted(by: { ascending ? $0.key < $1.key : $0.key > $1.key }) {
                flat.append(contentsOf: mg.items.filter { !$0.isWhatsApp }.sorted(by: byDate))
                flat.append(contentsOf: mg.items.filter { $0.isWhatsApp }.sorted(by: byDate))
            }
        }
        return BuiltGallery(items: items, flat: flat)
    }

    // MARK: - Stats

    private func computeStats(all: [MediaItem], done: [MonthGroup]) -> MediaStats {
        let doneKeys = Set(done.map { $0.key })
        let cal = Calendar.current
        func isDone(_ item: MediaItem) -> Bool {
            let y = cal.component(.year, from: item.dateTaken)
            let m = cal.component(.month, from: item.dateTaken)
            return doneKeys.contains(PreferencesManager.monthKey(year: y, month: m))
        }

        func counts(_ type: MediaType) -> (visible: Int, hidden: Int, vBytes: Int64, hBytes: Int64) {
            let items = all.filter { $0.type == type }
            let h = items.filter { isDone($0) }
            let v = items.filter { !isDone($0) }
            return (v.count, h.count, v.reduce(0) { $0 + $1.size }, h.reduce(0) { $0 + $1.size })
        }

        let (vp, hp, vpb, hpb) = counts(.image)
        let (vv, hv, vvb, hvb) = counts(.video)
        let (vd, hd, vdb, hdb) = counts(.pdf)
        let (va, ha, vab, hab) = counts(.audio)

        return MediaStats(
            visiblePhotos: vp, hiddenPhotos: hp, totalPhotos: vp + hp,
            visibleVideos: vv, hiddenVideos: hv, totalVideos: vv + hv,
            visiblePdfs:   vd, hiddenPdfs:   hd, totalPdfs:   vd + hd,
            visibleAudios: va, hiddenAudios:  ha, totalAudios:  va + ha,
            visiblePhotoBytes: vpb, hiddenPhotoBytes: hpb,
            visibleVideoBytes: vvb, hiddenVideoBytes: hvb,
            visiblePdfBytes:   vdb, hiddenPdfBytes:   hdb,
            visibleAudioBytes: vab, hiddenAudioBytes:  hab
        )
    }
}

// MARK: - PHPhotoLibraryChangeObserver bridge

/// Wraps the Obj-C delegate protocol so GalleryViewModel can stay a pure Swift actor.
private final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void
    init(_ onChange: @escaping () -> Void) { self.onChange = onChange }
    func photoLibraryDidChange(_ changeInstance: PHChange) { onChange() }
}
