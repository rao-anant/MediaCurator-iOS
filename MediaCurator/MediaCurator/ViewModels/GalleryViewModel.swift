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
        self.expandedMonths    = prefs.getExpandedMonths()
        self.expandedSubGroups = prefs.getExpandedSubGroups()
        self.seenSubGroups     = prefs.getSeenSubGroups()
        self.stagedIDs         = prefs.getStagedForDeletion()

        self.lastBatchSize = prefs.getLastDeletedBatch().count

        // Observe Photos library changes (mirrors Android's ContentObserver)
        photoLibraryObserver = PhotoLibraryObserver { [weak self] in
            Task { @MainActor [weak self] in self?.loadMedia(forceRefresh: true) }
        }
        PHPhotoLibrary.shared().register(photoLibraryObserver!)
    }

    deinit {
        if let obs = photoLibraryObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(obs)
        }
    }

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
        let cal = Calendar.current
        for item in filtered {
            let y = cal.component(.year, from: item.dateTaken)
            let m = cal.component(.month, from: item.dateTaken)
            let key = "\(PreferencesManager.monthKey(year: y, month: m)):\(item.isWhatsApp ? "wa" : "cam")"
            presence[key, default: []].insert(item.type)
        }
        monthTypePresence = presence

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
        let built = buildGalleryItems(visible: visible, done: done, allMedia: typeFiltered)

        galleryItems   = built.items
        flatMediaItems = built.flat
        mediaStats     = computeStats(all: allMedia, done: done)
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

    func setSortMode(_ mode: SortMode) {
        guard mode != sortMode else { return }
        sortMode = mode
        prefs.saveSortMode(mode)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    // MARK: - Expand / Collapse

    func toggleYearExpansion(_ year: Int) {
        if expandedYears.contains(year) { expandedYears.remove(year) }
        else { expandedYears.insert(year) }
        prefs.saveExpandedYears(expandedYears)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    func toggleMonthExpansion(_ key: String) {
        if expandedMonths.contains(key) { expandedMonths.remove(key) }
        else { expandedMonths.insert(key) }
        prefs.saveExpandedMonths(expandedMonths)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    func toggleSubGroupExpansion(_ key: String) {
        if expandedSubGroups.contains(key) { expandedSubGroups.remove(key) }
        else {
            expandedSubGroups.insert(key)
            // Mark as "seen" per currently-enabled type: a type counts as reviewed only when
            // the sub-group is opened while that type's filter chip is on. Keys are
            // "<month>:<sub>:<type>", e.g. "2024-03:cam:video". Persisted, grows only.
            var changed = false
            for type in enabledTypes where seenSubGroups.insert("\(key):\(type.rawValue)").inserted {
                changed = true
            }
            if changed { prefs.saveSeenSubGroups(seenSubGroups) }
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
        let activeCount = [includePhoto, includeVideo, includePdf, includeAudio].filter { $0 }.count
        if isOn && activeCount == 1 { return false }   // can't disable the last active filter

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
                // Offer "Hide Month" only once EVERY (sub-group, type) that actually exists in
                // the month has been reviewed — i.e. the sub-group was opened while that type's
                // chip was on. Uses full type presence (chip-independent), so a disabled filter
                // can't reveal the button early. Persisted, so reviewing can span sessions.
                if monthFullyReviewed(mg.key) {
                    items.append(.footer(.init(monthKey: mg.key, structuralVersion: sv)))
                }
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
