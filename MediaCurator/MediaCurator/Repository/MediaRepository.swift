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

        return await Task.detached(priority: .userInitiated) {
            var items: [MediaItem] = []

            let imagesFetch = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions())
            let videoFetch  = PHAsset.fetchAssets(with: .video, options: Self.fetchOptions())

            imagesFetch.enumerateObjects { asset, _, _ in
                if let item = Self.mediaItem(from: asset, type: .image) { items.append(item) }
            }
            videoFetch.enumerateObjects { asset, _, _ in
                if let item = Self.mediaItem(from: asset, type: .video) { items.append(item) }
            }

            // Deduplicate by (displayName, size) — same strategy as Android
            let seen = NSMutableSet()
            let deduped = items.filter { item in
                let key = "\(item.displayName)_\(item.size)"
                if seen.contains(key) { return false }
                seen.add(key)
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

    private static func mediaItem(from asset: PHAsset, type: MediaType) -> MediaItem? {
        // The PHAssetResource lookup is best-effort: it can be empty for some assets
        // (e.g. simulator-imported media). We must NOT drop the asset in that case —
        // fall back to identifier-derived values so every asset is still surfaced.
        let resource = PHAssetResource.assetResources(for: asset).first

        let dateTaken = asset.creationDate ?? asset.modificationDate ?? Date()
        let size      = (resource?.value(forKey: "fileSize") as? Int64) ?? 0
        let name      = resource?.originalFilename
            ?? String(asset.localIdentifier.prefix(8)) + (type == .video ? ".mov" : ".jpg")

        // Best-effort relative-path hint; we mostly care about detecting "whatsapp".
        let relativePath = name.localizedCaseInsensitiveContains("whatsapp") ? "WhatsApp/" : ""

        return MediaItem(
            id: asset.localIdentifier,
            localIdentifier: asset.localIdentifier,
            dateTaken: dateTaken,
            displayName: name,
            size: size,
            type: type,
            duration: asset.duration,
            relativePath: relativePath
        )
    }
}
