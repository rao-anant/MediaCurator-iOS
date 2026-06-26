import Foundation
import Combine

/// The app-managed trash: items staged for deletion. They still live in the Photos library
/// (hidden in the app) until the user commits the batch here, which deletes them in a single
/// PHAsset operation (one iOS confirmation). Mirrors Android's `TrashViewModel` in spirit,
/// adapted to iOS's "nothing is deleted until you say so" model.
@MainActor
final class TrashViewModel: ObservableObject {

    @Published var items: [MediaItem] = []
    @Published var isLoading = false
    @Published var isCommitting = false

    private let repo  = MediaRepository()
    private let prefs = PreferencesManager()
    private let trashManager = TrashManager.shared

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    func load() {
        Task {
            isLoading = true
            defer { isLoading = false }

            let media   = await MediaCache.shared.get(repo: repo)
            let liveIDs = Set(media.map(\.id))
            // Reconcile: drop staged ids that no longer exist in the library.
            let staged  = prefs.getStagedForDeletion().intersection(liveIDs)
            prefs.setStagedForDeletion(staged)

            items = media.filter { staged.contains($0.id) }
                .sorted { $0.dateTaken > $1.dateTaken }
        }
    }

    /// Remove one item from the trash (un-stage) — it returns to the gallery.
    func restore(_ item: MediaItem) {
        var staged = prefs.getStagedForDeletion()
        staged.remove(item.id)
        prefs.setStagedForDeletion(staged)
        items.removeAll { $0.id == item.id }
    }

    /// Un-stage everything.
    func restoreAll() {
        prefs.setStagedForDeletion([])
        items = []
    }

    /// Commit the whole batch: delete the staged assets from Photos. iOS shows ONE
    /// confirmation alert for the batch; on confirm they move to Recently Deleted.
    func emptyTrash() async {
        guard !items.isEmpty else { return }
        isCommitting = true
        defer { isCommitting = false }

        let toDelete = items
        let result = await trashManager.trash(toDelete)
        guard result.count > 0 else { return }   // user cancelled the system alert

        prefs.setStagedForDeletion([])
        prefs.setLastDeletedBatch(toDelete.map { ($0.localIdentifier, $0.size) })
        items = []
        await MediaCache.shared.invalidate()
    }
}
