import SwiftUI
import Photos

/// Pinch-to-zoom photo viewer — mirrors Android's `PhotoViewerActivity` / PhotoView library.
/// Uses SwiftUI's native MagnificationGesture + UIScrollView for smooth zoom.
struct PhotoZoomView: View {

    let localIdentifier: String

    @State private var image: UIImage? = nil
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1 {
                                        withAnimation(.spring) { scale = 1; offset = .zero }
                                        lastScale = 1; lastOffset = .zero
                                    }
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            guard scale > 1 else { return }
                                            offset = CGSize(
                                                width:  lastOffset.width  + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in lastOffset = offset }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring) {
                                if scale > 1 { scale = 1; offset = .zero; lastScale = 1; lastOffset = .zero }
                                else { scale = 2.5; lastScale = 2.5 }
                            }
                        }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: localIdentifier) { await loadImage() }
    }

    private func loadImage() async {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true

        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: opts
            ) { img, _ in
                if let img { Task { @MainActor in self.image = img } }
                continuation.resume()
            }
        }
    }
}
