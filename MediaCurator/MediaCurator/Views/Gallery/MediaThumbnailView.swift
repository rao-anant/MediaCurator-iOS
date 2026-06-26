import SwiftUI
import Photos

/// A single media thumbnail cell in the gallery grid.
/// Mirrors Android's `GalleryAdapter` thumbnail binding.
struct MediaThumbnailView: View {

    let cell: GalleryItem.MediaCell
    let onTap: () -> Void

    @State private var image: UIImage? = nil
    /// Pixel target for the thumbnail request; the view itself fills its grid cell.
    private let requestPx: CGFloat = 220

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Group {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                Image(systemName: iconName)
                                    .foregroundStyle(.tertiary)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .clipped()

                // Duration badge for video (bottom-leading)
                if cell.mediaItem.type == .video && cell.mediaItem.duration > 0 {
                    badge(durationString(cell.mediaItem.duration), bold: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                // File-size badge (bottom-trailing) — always shown
                badge(Formatters.bytes(cell.mediaItem.size))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                // Date badge in flat ("largest files") mode (top-leading)
                if let label = cell.dateLabel {
                    badge(label)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: cell.mediaItem.id) { await loadThumbnail() }
    }

    private func badge(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(bold ? .bold : .regular)
            .foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .padding(3)
    }

    // MARK: - Thumbnail loading

    private func loadThumbnail() async {
        let id = cell.mediaItem.localIdentifier
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else { return }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false

        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: requestPx, height: requestPx),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in
                if let img {
                    Task { @MainActor in self.image = img }
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Helpers

    private var iconName: String {
        switch cell.mediaItem.type {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .pdf:   return "doc.text"
        }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
