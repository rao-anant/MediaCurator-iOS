import SwiftUI
import Photos
import AVKit

/// A pager page that plays a Photos-library video (spec §4). Loads the `PHAsset`'s `AVPlayerItem`,
/// auto-plays when it becomes the current page, pauses when swiped away.
struct VideoPlayerPage: View {
    let localIdentifier: String
    let isCurrent: Bool

    @State private var player: AVPlayer? = nil
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if loading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            }
        }
        .task(id: localIdentifier) { await load() }
        .onChange(of: isCurrent) { current in
            if current { player?.seek(to: .zero); player?.play() }
            else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        loading = true
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { loading = false; return }

        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .automatic

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { item, _ in
                Task { @MainActor in
                    if let item {
                        let p = AVPlayer(playerItem: item)
                        p.isMuted = false
                        self.player = p
                        if isCurrent { p.play() }
                    }
                    self.loading = false
                    cont.resume()
                }
            }
        }
    }
}
