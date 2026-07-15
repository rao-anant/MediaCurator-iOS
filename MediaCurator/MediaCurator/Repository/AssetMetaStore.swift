import Foundation

/// Caches each asset's size + original filename, keyed by `localIdentifier`, so a full-library
/// re-scan does NOT pay for a synchronous `PHAssetResource.assetResources(for:)` CoreData
/// round-trip on every asset every time.
///
/// Those per-asset PhotoKit lookups are the expensive part of a scan. At a large library's scale
/// they saturate PhotoKit's single database context; when the app is backgrounded mid-scan, iOS's
/// PhotoKit background handler blocks the main thread waiting for that backlog to drain and trips
/// the 10-second scene-update watchdog (0x8BADF00D SIGKILL). Serving known assets from this cache
/// means only brand-new assets are ever looked up, so re-scans are cheap and don't stall.
///
/// Staleness is benign: an asset's id is stable, and if an edit changes its bytes the cached size
/// is at worst slightly off for sorting/stats until the entry is refreshed — never a correctness
/// bug. Mirrors the incremental-cache pattern of `PhotoHashStore`.
final class AssetMetaStore {

    static let shared = AssetMetaStore()
    private init() {}

    struct Meta: Codable { let size: Int64; let filename: String }

    private var cache: [String: Meta] = [:]
    private var loaded = false
    private let lock = NSLock()

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("asset_meta_cache.json")
    }

    /// A snapshot of the current cache, loading from disk on first use. Read once before a scan so
    /// the hot per-item path is a plain dictionary lookup with no locking.
    func snapshot() -> [String: Meta] {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode([String: Meta].self, from: data) {
                cache = decoded
            }
        }
        return cache
    }

    /// Merge entries looked up during a scan and persist. No-op when nothing new was found.
    func merge(_ new: [String: Meta]) {
        guard !new.isEmpty else { return }
        lock.lock()
        for (k, v) in new { cache[k] = v }
        let toWrite = cache
        lock.unlock()
        if let data = try? JSONEncoder().encode(toWrite) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
