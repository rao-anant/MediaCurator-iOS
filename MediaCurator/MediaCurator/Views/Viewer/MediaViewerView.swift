import SwiftUI
import Photos

/// Full-screen paging viewer — mirrors Android's `MediaViewerActivity`.
/// Pages through the gallery's live visible items, with a deferred-delete + undo flow
/// owned by `GalleryViewModel`.
struct MediaViewerView: View {

    @ObservedObject var vm: GalleryViewModel
    let startingID: String
    /// When true, paging is limited to the opened photo's month (gallery behavior — you can't
    /// swipe left past the first or right past the last photo of the month). The place / hidden /
    /// search viewers seed the vm with exactly the items to show, so they page the whole seeded
    /// list (monthScoped = false).
    var monthScoped: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String
    @State private var showControls = true
    /// When an undo restores an item, jump the pager back to it once it reappears.
    @State private var returnToID: String? = nil
    @State private var lastDeletedID: String? = nil
    /// Year+month to page within (nil = page all of `vm.flatMediaItems`).
    @State private var scopeYM: DateComponents?

    init(vm: GalleryViewModel, startingID: String, monthScoped: Bool = false) {
        self.vm = vm
        self.startingID = startingID
        self.monthScoped = monthScoped
        _currentID = State(initialValue: startingID)
        if monthScoped, let start = vm.flatMediaItems.first(where: { $0.id == startingID }) {
            _scopeYM = State(initialValue: Calendar.current.dateComponents([.year, .month], from: start.dateTaken))
        } else {
            _scopeYM = State(initialValue: nil)
        }
    }

    /// The pageable items — the whole seeded list, or just the opened photo's month (gallery).
    /// A paged TabView doesn't wrap, so scoping to the month gives the "stops at the ends" behavior.
    private var items: [MediaItem] {
        guard let ym = scopeYM else { return vm.flatMediaItems }
        let cal = Calendar.current
        return vm.flatMediaItems.filter {
            let c = cal.dateComponents([.year, .month], from: $0.dateTaken)
            return c.year == ym.year && c.month == ym.month
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    Group {
                        if item.type == .video {
                            VideoPlayerPage(localIdentifier: item.localIdentifier, isCurrent: item.id == currentID)
                        } else {
                            PhotoZoomView(localIdentifier: item.localIdentifier)
                        }
                    }
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

            HStack(spacing: 36) {
                // Share — opens the system share sheet for the current photo.
                actionIcon("square.and.arrow.up") { shareCurrentItem() }
                // Delete — moves to Recently Deleted (via the deferred-delete + undo flow).
                actionIcon("trash", tint: .red) { deleteCurrentItem() }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.4))
        }
        .transition(.opacity)
    }

    private func actionIcon(_ systemName: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
        }
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

    private func shareCurrentItem() {
        guard let item = currentItem else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [item.localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: opts
        ) { image, _ in
            guard let image else { return }
            Task { @MainActor in presentShareSheet(items: [image]) }
        }
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
