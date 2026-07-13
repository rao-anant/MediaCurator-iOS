import Foundation
import Photos
import CryptoKit

/// Computes and caches exact-content hashes (SHA-256 of the asset's primary resource bytes)
/// for duplicate detection. Mirrors Android's `PhotoHashStore` (which used MD5).
/// Cache key is (localIdentifier, size); persisted to Application Support as JSON.
actor PhotoHashStore {

    static let shared = PhotoHashStore()
    private init() {}

    private struct Entry: Codable { let size: Int64; let hash: String }
    private var cache: [String: Entry] = [:]
    private var loaded = false
    /// New hashes since the last disk write. We persist every `flushEvery` so a background
    /// kill loses at most that many (which just get recomputed on resume) — instead of rewriting
    /// the whole cache on every single item (O(n²) for a big library). Mirrors Android's 20–50.
    private var sinceFlush = 0
    private let flushEvery = 25

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("photo_hash_cache.json")
    }

    func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Number of cached entries (for the "N files indexed" subtitle).
    func count() -> Int { cache.count }

    /// Force-write any pending hashes to disk (call when a hashing pass finishes).
    func flush() {
        guard sinceFlush > 0 else { return }
        persist(); sinceFlush = 0
    }

    /// Return the content hash for an item, computing and caching it on first request.
    /// Returns nil if the bytes can't be read.
    func hash(for item: MediaItem) async -> String? {
        ensureLoaded()
        if let e = cache[item.id], e.size == item.size { return e.hash }
        guard let h = await Self.computeHash(localIdentifier: item.localIdentifier) else { return nil }
        cache[item.id] = Entry(size: item.size, hash: h)
        sinceFlush += 1
        if sinceFlush >= flushEvery { persist(); sinceFlush = 0 }
        return h
    }

    private static func computeHash(localIdentifier: String) async -> String? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject,
              let resource = PHAssetResource.assetResources(for: asset).first
        else { return nil }

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var hasher = SHA256()
            PHAssetResourceManager.default().requestData(
                for: resource, options: opts,
                dataReceivedHandler: { hasher.update(data: $0) },
                completionHandler: { error in
                    if error != nil {
                        cont.resume(returning: nil)
                    } else {
                        let digest = hasher.finalize()
                        cont.resume(returning: digest.map { String(format: "%02x", $0) }.joined())
                    }
                }
            )
        }
    }
}
