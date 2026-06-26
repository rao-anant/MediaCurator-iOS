import UIKit
import Photos

/// Present the system share sheet for arbitrary items from anywhere in the app.
@MainActor
func presentShareSheet(items: [Any]) {
    guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
          let root = scene.keyWindow?.rootViewController
    else { return }

    var top = root
    while let presented = top.presentedViewController { top = presented }

    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    vc.popoverPresentationController?.sourceView = top.view
    vc.popoverPresentationController?.sourceRect = CGRect(
        x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 0, height: 0)
    top.present(vc, animated: true)
}

/// Fetch full-size images for the given items and present a share sheet with them.
@MainActor
func shareItems(_ items: [MediaItem]) {
    let ids = items.map(\.localIdentifier)
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    var phAssets: [PHAsset] = []
    assets.enumerateObjects { a, _, _ in phAssets.append(a) }
    guard !phAssets.isEmpty else { return }

    let opts = PHImageRequestOptions()
    opts.isNetworkAccessAllowed = true
    opts.deliveryMode = .highQualityFormat

    var images: [UIImage] = []
    let group = DispatchGroup()
    for asset in phAssets {
        group.enter()
        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize,
            contentMode: .default, options: opts
        ) { image, _ in
            if let image { images.append(image) }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        guard !images.isEmpty else { return }
        presentShareSheet(items: images)
    }
}
