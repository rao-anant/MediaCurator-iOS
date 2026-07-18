import SwiftUI
import Photos

/// A single media thumbnail cell in the gallery grid.
/// Mirrors Android's `GalleryAdapter` thumbnail binding.
struct MediaThumbnailView: View {

    let cell: GalleryItem.MediaCell
    /// Pixel size to request the thumbnail at — the true cell size (from the parent's stable
    /// viewport width) so it's crisp on iPad without re-firing during layout. Other grids
    /// (Trash, Duplicates) use the default, which is sharp enough for their larger cells.
    var targetPx: CGFloat = 500
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    var onLongPress: (() -> Void)? = nil

    @State private var image: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            // A fixed square cell sized to the column width; the image fills it and is clipped, so
            // every thumbnail is identical in size and none overflow into (obscure) their neighbours.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.secondarySystemBackground))
                            .overlay(Image(systemName: iconName).foregroundStyle(.tertiary))
                    }
                }
                .clipped()
                // Duration badge for video (bottom-leading)
                .overlay(alignment: .bottomLeading) {
                    if cell.mediaItem.type == .video && cell.mediaItem.duration > 0 {
                        badge(durationString(cell.mediaItem.duration), bold: true)
                    }
                }
                // File-size badge (bottom-trailing) — always shown
                .overlay(alignment: .bottomTrailing) {
                    badge(Formatters.bytes(cell.mediaItem.size))
                }
                // Date badge in flat ("largest files") mode (top-leading)
                .overlay(alignment: .topLeading) {
                    if let label = cell.dateLabel { badge(label) }
                }
                // Selection overlay
                .overlay {
                    if isSelecting {
                        ZStack {
                            Color.black.opacity(isSelected ? 0.25 : 0.0)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? Color.accentColor : .white)
                                .shadow(radius: 1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(4)
                        }
                    }
                }
                .contentShape(Rectangle())
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress?() }
        )
        // Load once per cell at the parent's stable pixel target (keyed on both so a rotation /
        // split-view resize re-requests, but scrolling and month expansion do not — no flicker).
        .task(id: "\(cell.mediaItem.id)|\(Int(targetPx))") {
            await loadThumbnail(targetPx: targetPx)
        }
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

    private func loadThumbnail(targetPx: CGFloat) async {
        // Screenshot-test hook only: skip the PHImageManager request, which pops the (untappable)
        // photo-permission prompt on the sim. The placeholder tile is enough to verify layout.
        if UITestHooks.synthetic { return }
        let id = cell.mediaItem.localIdentifier
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else { return }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false

        // `.opportunistic` delivers the completion handler MORE THAN ONCE (a fast low-res
        // thumbnail, then the full-quality image). A checked continuation may only be resumed
        // once — resuming twice is a fatal error — so resume on the first callback and let any
        // later, higher-quality delivery keep updating the image.
        var resumed = false
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: targetPx, height: targetPx),
                contentMode: .aspectFill,
                options: opts
            ) { img, _ in
                if let img {
                    Task { @MainActor in self.image = img }
                }
                if !resumed {
                    resumed = true
                    continuation.resume()
                }
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
