import SwiftUI
import Photos

/// A single media thumbnail cell in the gallery grid.
/// Mirrors Android's `GalleryAdapter` thumbnail binding.
struct MediaThumbnailView: View {

    let cell: GalleryItem.MediaCell
    let onTap: () -> Void

    @State private var image: UIImage? = nil
    private let size: CGFloat = 100

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
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
                .frame(width: size, height: size)
                .clipped()

                // Duration badge for video
                if cell.mediaItem.type == .video && cell.mediaItem.duration > 0 {
                    Text(durationString(cell.mediaItem.duration))
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .padding(3)
                }

                // Date badge in SIZE_ABSOLUTE flat mode
                if let label = cell.dateLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: cell.mediaItem.id) { await loadThumbnail() }
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
                targetSize: CGSize(width: size * 2, height: size * 2),
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
