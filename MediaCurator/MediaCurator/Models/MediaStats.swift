import Foundation

/// Aggregate counts and sizes across all media types and visibility states.
/// Mirrors Android's `MediaStats` data class.
struct MediaStats {
    // Counts
    let visiblePhotos: Int;  let hiddenPhotos: Int;  let totalPhotos: Int
    let visibleVideos: Int;  let hiddenVideos: Int;  let totalVideos: Int
    let visiblePdfs: Int;    let hiddenPdfs: Int;    let totalPdfs: Int
    let visibleAudios: Int;  let hiddenAudios: Int;  let totalAudios: Int

    // Sizes in bytes
    let visiblePhotoBytes: Int64;  let hiddenPhotoBytes: Int64
    let visibleVideoBytes: Int64;  let hiddenVideoBytes: Int64
    let visiblePdfBytes: Int64;    let hiddenPdfBytes: Int64
    let visibleAudioBytes: Int64;  let hiddenAudioBytes: Int64

    static let empty = MediaStats(
        visiblePhotos: 0, hiddenPhotos: 0, totalPhotos: 0,
        visibleVideos: 0, hiddenVideos: 0, totalVideos: 0,
        visiblePdfs: 0,   hiddenPdfs: 0,   totalPdfs: 0,
        visibleAudios: 0, hiddenAudios: 0, totalAudios: 0,
        visiblePhotoBytes: 0, hiddenPhotoBytes: 0,
        visibleVideoBytes: 0, hiddenVideoBytes: 0,
        visiblePdfBytes: 0,   hiddenPdfBytes: 0,
        visibleAudioBytes: 0, hiddenAudioBytes: 0
    )
}
