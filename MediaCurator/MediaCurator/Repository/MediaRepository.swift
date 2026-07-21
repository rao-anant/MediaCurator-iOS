import Foundation
import Photos

/// Fetches and processes media from the Photos library.
/// Mirrors Android's `MediaRepository` — all I/O is async, call off the main thread.
final class MediaRepository {

    private let prefs: PreferencesManager

    init(prefs: PreferencesManager = PreferencesManager()) {
        self.prefs = prefs
    }

    // MARK: - Fetch

    /// Fetches ALL assets (images, video, audio) from the Photos library.
    /// PDFs are not in the Photos library on iOS; they are handled separately via FileManager.
    func fetchAllMedia() async -> [MediaItem] {
        // Screenshot-test hook only: return a synthetic tree with NO PhotoKit access at all, so the
        // (untappable) photo-permission prompt never fires. Lets gallery LAYOUT be verified headlessly.
        if UITestHooks.synthetic { return Self.syntheticTestMedia() }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        // Load the size/filename cache once up front so the per-asset loop below is a plain
        // dictionary hit for known assets — avoiding a synchronous PhotoKit lookup per item, which
        // at scale stalls PhotoKit and trips the background watchdog. New assets are collected and
        // persisted after the scan.
        let metaCache = AssetMetaStore.shared.snapshot()

        return await Task.detached(priority: .userInitiated) {
            var items: [MediaItem] = []
            var newMeta: [String: AssetMetaStore.Meta] = [:]

            let imagesFetch = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions())
            let videoFetch  = PHAsset.fetchAssets(with: .video, options: Self.fetchOptions())

            imagesFetch.enumerateObjects { asset, _, _ in
                if let (item, fresh) = Self.mediaItem(from: asset, type: .image, cache: metaCache) {
                    items.append(item)
                    if let fresh { newMeta[asset.localIdentifier] = fresh }
                }
            }
            videoFetch.enumerateObjects { asset, _, _ in
                if let (item, fresh) = Self.mediaItem(from: asset, type: .video, cache: metaCache) {
                    items.append(item)
                    if let fresh { newMeta[asset.localIdentifier] = fresh }
                }
            }
            AssetMetaStore.shared.merge(newMeta)

            // Deduplicate by asset identity (localIdentifier) only — NOT by (name, size). Two real
            // duplicate photos share a name and size but are distinct assets; keying on (name, size)
            // silently dropped one of every exact-duplicate pair, so the Duplicates feature could
            // never find them. localIdentifier is unique per asset, so this just guards against the
            // same asset appearing twice while keeping genuine duplicates in the list.
            let seen = NSMutableSet()
            let deduped = items.filter { item in
                if seen.contains(item.id) { return false }
                seen.add(item.id)
                return true
            }

            return deduped
        }.value
    }

    /// Groups a flat item list into `MonthGroup` buckets and splits into visible / done.
    func processAndGroupMedia(
        _ items: [MediaItem]
    ) -> (visible: [MonthGroup], done: [MonthGroup]) {
        let doneMonths = prefs.getDoneMonths()
        var byKey: [String: MonthGroup] = [:]
        let cal = Calendar.current

        for item in items {
            let comps = cal.dateComponents([.year, .month], from: item.dateTaken)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = PreferencesManager.monthKey(year: year, month: month)
            if byKey[key] == nil {
                byKey[key] = MonthGroup(year: year, month: month, items: [])
            }
            byKey[key]!.items.append(item)
        }

        // Sort months descending
        let sorted = byKey.values.sorted { a, b in
            a.key > b.key
        }

        var visible: [MonthGroup] = []
        var done: [MonthGroup] = []
        for group in sorted {
            if doneMonths.contains(group.key) { done.append(group) }
            else { visible.append(group) }
        }
        return (visible, done)
    }

    /// Synthetic gallery tree for the `-uiGalleryScroll` screenshot hook (no PhotoKit). April 2024
    /// has both a Camera (15) and a WhatsApp (8) sub-group and enough items to scroll.
    static func syntheticTestMedia() -> [MediaItem] {
        var items: [MediaItem] = []
        let cal = Calendar.current
        func add(_ y: Int, _ m: Int, _ count: Int, wa: Bool) {
            for i in 0..<count {
                let date = cal.date(from: DateComponents(year: y, month: m, day: min(1 + i, 27), hour: 12)) ?? Date()
                let n = items.count
                items.append(MediaItem(
                    id: "test-\(n)", localIdentifier: "test-\(n)", dateTaken: date,
                    displayName: wa ? "whatsapp_\(y)\(m)_\(i).jpg" : "IMG_\(y)\(m)_\(i).jpg",
                    size: Int64(500_000 + i * 12_345), type: .image, duration: 0,
                    relativePath: wa ? "DCIM/WhatsApp Images/" : "DCIM/Camera/"))
            }
        }
        // crossYear needs enough content BELOW an open month to scroll that month clean off the top
        // (the standard set is only ~1.5 screens, so an open month's tail always stays visible — which
        // is exactly why it can't exhibit the scrolled-past-open-month state). Give it a tall open
        // April plus a full year of collapsed months after it, then 2025/2026.
        if UITestHooks.crossYear {
            add(2024, 2, 12, wa: false)
            add(2024, 4, 40, wa: false); add(2024, 4, 8, wa: true)
            for m in 5...12 { add(2024, m, 8 + m, wa: false) }
            for m in 1...12 { add(2025, m, 6 + m, wa: false) }
            add(2026, 2, 10, wa: false); add(2026, 5, 10, wa: false)
            return items
        }
        add(2024, 2, 12, wa: false)
        add(2024, 4, 40, wa: false); add(2024, 4, 8, wa: true)   // big enough to scroll the header off
        add(2024, 7, 15, wa: false)
        add(2024, 9, 12, wa: false)
        add(2024, 11, 15, wa: false)
        add(2025, 1, 10, wa: false)
        add(2025, 6, 10, wa: false)
        add(2026, 2, 10, wa: false)
        return items
    }

    // MARK: - Private helpers

    private static func fetchOptions() -> PHFetchOptions {
        let opts = PHFetchOptions()
        opts.includeHiddenAssets = false
        opts.includeAllBurstAssets = false
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return opts
    }

    /// Builds a `MediaItem` for an asset. Returns the item plus, when the asset's size/filename had
    /// to be looked up fresh (cache miss), the `Meta` to persist — nil `fresh` means it was served
    /// from cache and nothing new needs saving.
    private static func mediaItem(from asset: PHAsset, type: MediaType,
                                  cache: [String: AssetMetaStore.Meta]) -> (MediaItem, AssetMetaStore.Meta?)? {
        let id = asset.localIdentifier
        let size: Int64
        let name: String
        var fresh: AssetMetaStore.Meta? = nil

        if let cached = cache[id] {
            size = cached.size
            name = cached.filename
        } else {
            // The PHAssetResource lookup is best-effort: it can be empty for some assets
            // (e.g. simulator-imported media). We must NOT drop the asset in that case —
            // fall back to identifier-derived values so every asset is still surfaced.
            let resource = PHAssetResource.assetResources(for: asset).first
            size = (resource?.value(forKey: "fileSize") as? Int64) ?? 0
            name = resource?.originalFilename
                ?? String(asset.localIdentifier.prefix(8)) + (type == .video ? ".mov" : ".jpg")
            fresh = AssetMetaStore.Meta(size: size, filename: name)
        }

        let dateTaken = asset.creationDate ?? asset.modificationDate ?? Date()

        // Best-effort relative-path hint; we mostly care about detecting "whatsapp".
        let relativePath = name.localizedCaseInsensitiveContains("whatsapp") ? "WhatsApp/" : ""

        return (MediaItem(
            id: asset.localIdentifier,
            localIdentifier: asset.localIdentifier,
            dateTaken: dateTaken,
            displayName: name,
            size: size,
            type: type,
            duration: asset.duration,
            relativePath: relativePath
        ), fresh)
    }
}
