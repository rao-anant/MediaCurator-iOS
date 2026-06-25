import Foundation
import Photos

/// Soft-delete abstraction.
/// On iOS, Photos deletion always goes to the system "Recently Deleted" album (30-day retention).
/// There is no dual-impl split needed unlike Android — PHAssetChangeRequest handles all versions.
/// Mirrors Android's `TrashManager` interface.
final class TrashManager {

    nonisolated(unsafe) static let shared = TrashManager()
    private init() {}

    // MARK: - Trash (move to Recently Deleted)

    @discardableResult
    func trash(_ items: [MediaItem]) async -> TrashResult {
        let assets = fetchAssets(for: items)
        guard !assets.isEmpty else { return TrashResult(count: 0, bytes: 0, identifiers: []) }

        var success = false
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }
            success = true
        } catch {
            success = false
        }

        guard success else { return TrashResult(count: 0, bytes: 0, identifiers: []) }
        let bytes = items.reduce(0) { $0 + $1.size }
        let ids   = items.map { $0.localIdentifier }
        return TrashResult(count: items.count, bytes: bytes, identifiers: ids)
    }

    // MARK: - Restore

    /// On iOS, restoration from Recently Deleted requires the user to do it manually
    /// in the Photos app. We surface a message rather than silently no-op.
    func restore(_ identifiers: [String]) async -> TrashResult {
        // PHPhotoLibrary has no public API to restore from Recently Deleted.
        // Return empty result; callers should inform the user to use Photos.app.
        return TrashResult(count: 0, bytes: 0, identifiers: [])
    }

    // MARK: - Private

    private func fetchAssets(for items: [MediaItem]) -> [PHAsset] {
        let ids = items.map { $0.localIdentifier }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}

struct TrashResult {
    let count: Int
    let bytes: Int64
    let identifiers: [String]
}
