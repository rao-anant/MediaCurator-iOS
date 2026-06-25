import Foundation

/// A set of photos with the same MD5 hash.
/// Mirrors Android's `DuplicateGroup` data class.
struct DuplicateGroup: Identifiable {
    let md5: String
    let items: [MediaItem]
    /// Index of the copy the user wants to keep; all others are candidates for deletion.
    var keepIndex: Int = 0

    var id: String { md5 }

    /// Bytes that would be freed by deleting all but the kept copy.
    var reclaimableBytes: Int64 {
        items.reduce(0) { $0 + $1.size } - items[keepIndex].size
    }
}
