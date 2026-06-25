import SwiftUI
import Photos

/// Full-screen paging viewer — mirrors Android's `MediaViewerActivity`.
/// Pages through the gallery's live visible items, with a deferred-delete + undo flow
/// owned by `GalleryViewModel`.
struct MediaViewerView: View {

    @ObservedObject var vm: GalleryViewModel
    let startingID: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var showControls = true
    /// When an undo restores an item, jump the pager back to it once it reappears.
    @State private var returnToID: String? = nil
    @State private var lastDeletedID: String? = nil

    init(vm: GalleryViewModel, startingID: String) {
        self.vm = vm
        self.startingID = startingID
        _currentID = State(initialValue: startingID)
    }

    private var items: [MediaItem] { vm.flatMediaItems }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    PhotoZoomView(localIdentifier: item.localIdentifier)
                        .tag(item.id)
                        .onTapGesture { withAnimation { showControls.toggle() } }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if showControls { controlsOverlay }

            if let undo = vm.pendingUndo { undoToast(undo) }
        }
        .preferredColorScheme(.dark)
        .onChange(of: items) { newItems in
            // An undo just restored a photo — jump back to it now that it's in the list.
            if let target = returnToID, newItems.contains(where: { $0.id == target }) {
                currentID = target
                returnToID = nil
                return
            }
            // If the visible list shrank past our selection (e.g. after a delete),
            // keep a valid selection or close when nothing remains.
            if newItems.isEmpty {
                dismiss()
            } else if !newItems.contains(where: { $0.id == currentID }) {
                currentID = newItems.first!.id
            }
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title3).foregroundStyle(.white)
                        .padding(10).background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if let item = currentItem {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.displayName)
                            .font(.caption).foregroundStyle(.white).lineLimit(1)
                        Text(Formatters.bytes(item.size))
                            .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding()
            .background(.black.opacity(0.4))

            Spacer()

            HStack {
                Spacer()
                Button(role: .destructive, action: deleteCurrentItem) {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.red.opacity(0.85), in: Capsule())
                }
                Spacer()
            }
            .padding(.bottom, 32)
            .background(.black.opacity(0.4))
        }
        .transition(.opacity)
    }

    private func undoToast(_ undo: GalleryViewModel.PendingUndo) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Text(undo.message).font(.subheadline)
                Button("Undo") {
                    returnToID = lastDeletedID
                    vm.undoDelete()
                }
                .font(.subheadline.bold())
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var currentItem: MediaItem? {
        items.first { $0.id == currentID }
    }

    private func deleteCurrentItem() {
        guard let item = currentItem else { return }
        lastDeletedID = item.id
        // Move selection to a neighbor first so the pager doesn't jump after the item vanishes.
        if let idx = items.firstIndex(where: { $0.id == currentID }) {
            let neighbor = idx + 1 < items.count ? items[idx + 1] : (idx - 1 >= 0 ? items[idx - 1] : nil)
            if let neighbor { currentID = neighbor.id }
        }
        vm.requestDelete([item])
    }
}
