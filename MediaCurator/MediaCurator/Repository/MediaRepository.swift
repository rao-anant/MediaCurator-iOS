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
