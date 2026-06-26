import SwiftUI

/// The gallery "settings bar" (spec §3): one chip per media type with count + size and an
/// on/off state. Audio/PDF chips are hidden entirely when the library has none of that type.
struct FilterChipsBar: View {
    let stats: MediaStats
    let includePhoto: Bool
    let includeVideo: Bool
    let includePdf: Bool
    let includeAudio: Bool
    /// Returns false if the toggle was rejected (would leave zero filters active).
    let onToggle: (MediaType) -> Bool
    let onRejected: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.image, "photo", on: includePhoto,
                     total: stats.totalPhotos, hidden: stats.hiddenPhotos,
                     bytes: stats.visiblePhotoBytes + stats.hiddenPhotoBytes)
                chip(.video, "video", on: includeVideo,
                     total: stats.totalVideos, hidden: stats.hiddenVideos,
                     bytes: stats.visibleVideoBytes + stats.hiddenVideoBytes)
                // Audio / PDF chips only when the library actually has them.
                if stats.totalAudios > 0 {
                    chip(.audio, "waveform", on: includeAudio,
                         total: stats.totalAudios, hidden: stats.hiddenAudios,
                         bytes: stats.visibleAudioBytes + stats.hiddenAudioBytes)
                }
                if stats.totalPdfs > 0 {
                    chip(.pdf, "doc.text", on: includePdf,
                         total: stats.totalPdfs, hidden: stats.hiddenPdfs,
                         bytes: stats.visiblePdfBytes + stats.hiddenPdfBytes)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func chip(_ type: MediaType, _ icon: String, on: Bool,
                      total: Int, hidden: Int, bytes: Int64) -> some View {
        let countText = hidden > 0 ? "\(total)/\(hidden)" : "\(total)"
        return Button {
            if !onToggle(type) { onRejected() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countText).font(.caption).fontWeight(.medium)
                    Text(Formatters.bytes(bytes)).font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(on ? Color.green : Color.red)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(on ? Color.green.opacity(0.6) : Color.red.opacity(0.4), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            )
            .opacity(on ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }
}
