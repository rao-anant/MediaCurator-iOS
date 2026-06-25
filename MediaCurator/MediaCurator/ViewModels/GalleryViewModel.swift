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

    /// Non-nil while an undo window is open after a delete. Drives the undo toast.
    @Published var pendingUndo: PendingUndo? = nil

    struct PendingUndo: Equatable {
        let message: String
        let count: Int
    }

    /// Seconds the "Undo" toast stays up before the deletion is committed to Photos.
    /// Once committed, the items are in the system's Recently Deleted and cannot be
    /// restored programmatically, so this window is the only chance to undo.
    private let undoWindowSeconds: UInt64 = 6

    // MARK: - Private

    let prefs: PreferencesManager
    private let repo: MediaRepository
    private let trashManager: TrashManager

    /// Items deleted this session — never cleared while app is running.
    /// Guards against MediaStore-equivalent lag where deleted items briefly reappear.
    private var sessionDeletedIDs: Set<String> = []

    /// Items hidden from the UI but NOT yet committed to Photos — the undo window is open.
    /// Deferring the actual PHAsset deletion is what makes undo possible (iOS has no API to
    /// restore from Recently Deleted once committed).
    private var pendingDeleteIDs: Set<String> = []
    private var pendingDeleteItems: [MediaItem] = []
    private var commitTask: Task<Void, Never>? = nil

    private var structuralVersion = 0
    private var expandedYears:     Set<Int>    = []
    private var expandedMonths:    Set<String> = []
    private var expandedSubGroups: Set<String> = []

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

        // Hide both committed session-deletes and items in the open undo window.
        let filtered = allMedia.filter {
            !sessionDeletedIDs.contains($0.id) && !pendingDeleteIDs.contains($0.id)
        }

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

    // MARK: - Deletion (deferred, with undo)

    /// Hide [items] immediately and open an undo window. The actual Photos deletion is
    /// committed only when the window expires (see `commitPendingDeletion`). Tapping undo
    /// before then cancels the commit and restores the items.
    func requestDelete(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        // If a previous undo window is still open, commit it now before starting a new one.
        if !pendingDeleteItems.isEmpty {
            commitTask?.cancel()
            let prior = pendingDeleteItems
            Task { await commitPendingDeletion(prior) }
        }

        for item in items { pendingDeleteIDs.insert(item.id) }
        pendingDeleteItems = items
        pendingUndo = PendingUndo(
            message: items.count == 1 ? "1 item deleted" : "\(items.count) items deleted",
            count: items.count
        )
        loadMedia(forceRefresh: false)   // re-filter from cache (cheap), hides the items

        commitTask?.cancel()
        commitTask = Task { [undoWindowSeconds] in
            try? await Task.sleep(nanoseconds: undoWindowSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await commitPendingDeletion(items)
        }
    }

    /// Cancel the pending commit and restore the hidden items.
    func undoDelete() {
        commitTask?.cancel()
        commitTask = nil
        for item in pendingDeleteItems { pendingDeleteIDs.remove(item.id) }
        pendingDeleteItems = []
        pendingUndo = nil
        loadMedia(forceRefresh: false)
    }

    private func commitPendingDeletion(_ items: [MediaItem]) async {
        let result = await trashManager.trash(items)
        // Promote from "pending" to permanently session-deleted regardless of how many the
        // system reports trashed, so the UI never flickers them back.
        for item in items {
            pendingDeleteIDs.remove(item.id)
            sessionDeletedIDs.insert(item.id)
        }
        if pendingDeleteItems.map(\.id) == items.map(\.id) {
            pendingDeleteItems = []
            pendingUndo = nil
        }
        if result.count > 0 {
            prefs.setLastDeletedBatch(items.map { ($0.localIdentifier, $0.size) })
            lastBatchSize = items.count
        }
        await MediaCache.shared.invalidate()
        loadMedia(forceRefresh: true)
    }

    // MARK: - Done months

    func markMonthDone(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        prefs.markMonthDone(year: y, month: m)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    func unmarkMonthDone(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        prefs.unmarkMonthDone(year: y, month: m)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
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
        else { expandedSubGroups.insert(key) }
        prefs.saveExpandedSubGroups(expandedSubGroups)
        structuralVersion += 1
        loadMedia(forceRefresh: false)
    }

    // MARK: - Type filters

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

        // Tree mode: year → month → (cam subgroup / wa subgroup) → items
        // Group visible months by year
        var byYear: [Int: [MonthGroup]] = [:]
        for mg in visible {
            byYear[mg.year, default: []].append(mg)
        }
        let years = byYear.keys.sorted(by: >)

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

            for mg in monthGroups.sorted(by: { $0.key > $1.key }) {
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

                // Split into Camera & Others vs WhatsApp sub-groups
                let waItems  = mg.items.filter { $0.isWhatsApp }
                let camItems = mg.items.filter { !$0.isWhatsApp }

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
                items.append(.footer(.init(monthKey: mg.key, structuralVersion: sv)))
            }
        }

        // The viewer pages through ALL visible items regardless of which groups are
        // expanded in the tree, so build `flat` independently in display order
        // (year desc → month desc → Camera & Others, then WhatsApp).
        for year in years {
            for mg in byYear[year]!.sorted(by: { $0.key > $1.key }) {
                flat.append(contentsOf: mg.items.filter { !$0.isWhatsApp })
                flat.append(contentsOf: mg.items.filter { $0.isWhatsApp })
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
