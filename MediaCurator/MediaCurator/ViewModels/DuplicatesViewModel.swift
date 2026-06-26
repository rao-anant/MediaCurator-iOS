import Foundation
import Combine

/// Finds exact-duplicate photos/videos (identical content hash) so copies can be deleted.
/// Mirrors Android's `DuplicatesViewModel`. Deletion is soft — staged to the app trash.
@MainActor
final class DuplicatesViewModel: ObservableObject {

    @Published var groups: [DuplicateGroup] = []
    @Published var isComputing = false
    @Published var indexedCount = 0
    @Published var progress: (done: Int, total: Int)? = nil

    private let repo  = MediaRepository()
    private let prefs = PreferencesManager()
    private let hashStore = PhotoHashStore.shared

    /// Count of items marked for deletion across all groups (everything except each keep).
    var deleteCount: Int { groups.reduce(0) { $0 + ($1.items.count - 1) } }
    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }

    func compute() {
        Task {
            isComputing = true
            defer { isComputing = false; progress = nil }

            let media = await MediaCache.shared.get(repo: repo)
            // Only photos/videos have content hashes worth comparing here.
            let staged = prefs.getStagedForDeletion()
            let candidates = media.filter {
                ($0.type == .image || $0.type == .video) && !staged.contains($0.id)
            }

            var byHash: [String: [MediaItem]] = [:]
            for (i, item) in candidates.enumerated() {
                progress = (i + 1, candidates.count)
                if let h = await hashStore.hash(for: item) {
                    byHash[h, default: []].append(item)
                }
            }
            indexedCount = await hashStore.count()

            // Build groups of 2+; pre-select the largest copy as the one to KEEP.
            groups = byHash
                .filter { $0.value.count > 1 }
                .map { hash, items in
                    let sorted = items.sorted { $0.size > $1.size }
                    return DuplicateGroup(md5: hash, items: sorted, keepIndex: 0)
                }
                .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        }
    }

    /// Change which copy in a group is the kept one.
    func setKeep(groupID: String, index: Int) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].keepIndex = index
    }

    /// Stage every non-kept duplicate for deletion (soft → trash).
    func stageDuplicatesForDeletion() {
        var staged = prefs.getStagedForDeletion()
        for group in groups {
            for (idx, item) in group.items.enumerated() where idx != group.keepIndex {
                staged.insert(item.id)
            }
        }
        prefs.setStagedForDeletion(staged)
        groups = []   // cleared from this view; they're now in Trash
    }
}
