import Foundation

/// Process-wide cache of the full media fetch.
/// Whoever loads first pays for the scan; others reuse it.
/// Mirrors Android's `MediaCache` object.
actor MediaCache {

    nonisolated(unsafe) static let shared = MediaCache()
    private init() {}

    private var cached: [MediaItem]? = nil

    /// Return cached media, fetching once if absent or `forceRefresh` is true.
    func get(repo: MediaRepository, forceRefresh: Bool = false) async -> [MediaItem] {
        if let c = cached, !forceRefresh { return c }
        let fresh = await repo.fetchAllMedia()
        cached = fresh
        return fresh
    }

    /// Drop cache so the next `get` refetches (call after mutations).
    func invalidate() { cached = nil }

    /// Cached count without triggering a scan; -1 if nothing cached yet.
    var peekSize: Int { cached?.count ?? -1 }
}
