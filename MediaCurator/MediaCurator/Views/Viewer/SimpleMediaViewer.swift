import SwiftUI

/// Presents the full-screen `MediaViewerView` over a plain item list (from Hidden, Place browse,
/// or search) — screens that don't own the gallery tree. Seeds a throwaway `GalleryViewModel`
/// so delete/undo still route through the shared staged-Trash flow.
struct SimpleMediaViewer: View {
    let items: [MediaItem]
    let startingID: String
    @StateObject private var vm = GalleryViewModel()

    var body: some View {
        MediaViewerView(vm: vm, startingID: startingID)
            .onAppear { vm.seedViewer(items: items) }
    }
}
