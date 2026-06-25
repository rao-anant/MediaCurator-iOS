import Foundation
import Photos

/// Mirrors Android's `MediaItem` data class.
/// `localIdentifier` is the PHAsset identifier (replaces Android's MediaStore `id` + `uri`).
struct MediaItem: Identifiable, Hashable {
    let id: String              // PHAsset.localIdentifier
    let localIdentifier: String // same as id; explicit alias for clarity at call sites
    let dateTaken: Date
    let displayName: String
    let size: Int64             // bytes
    let type: MediaType
    let duration: TimeInterval  // seconds; 0 for non-video/audio
    let relativePath: String    // e.g. "DCIM/WhatsApp Images/" — derived from PHAsset source

    /// True when the item originates from a WhatsApp album/path.
    var isWhatsApp: Bool {
        relativePath.localizedCaseInsensitiveContains("whatsapp")
    }

    // MARK: Hashable
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
}
