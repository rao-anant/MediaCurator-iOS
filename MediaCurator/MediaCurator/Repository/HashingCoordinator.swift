import Foundation
import Combine

/// Continuously hashes the library in the background so the Duplicates screen is instant when
/// opened. **Photos are hashed first** and unlock Duplicates as soon as they finish; videos hash
/// afterward in the background (they are large — hashing all of them can take a long while, and
/// most duplicates are photos). The Home "Find duplicates" card shows photo progress and stays
/// disabled only until the photos are done.
///
/// Safety (this is heavy PhotoKit work — the subsystem behind the b22 background-watchdog crash):
/// hashing is **serial** — one asset at a time via `PhotoHashStore`'s actor — so it never fans out
/// enough concurrent `PHAssetResourceManager` reads to starve the cooperative pool. And it is
/// **cancelled when the app backgrounds** (`MediaCuratorApp` scenePhase), so no large read is in
/// flight during the scene-update transition. It resumes from the persisted cache on the next Home
/// load — already-hashed assets are cache hits, so a resume races through them.
@MainActor
final class HashingCoordinator: ObservableObject {

    static let shared = HashingCoordinator()
    private init() {}

    @Published private(set) var photosDone = 0
    @Published private(set) var photosTotal = 0
    /// Photos are fully hashed — Duplicates is usable. Videos may still be hashing in the background.
    @Published private(set) var photosComplete = false
    @Published private(set) var videosDone = 0
    @Published private(set) var videosTotal = 0
    /// Photos AND videos hashed.
    @Published private(set) var isComplete = false
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?
    private let hashStore = PhotoHashStore.shared

    /// Start (or resume) hashing. Photos first, then videos. Idempotent; a resume re-walks the list
    /// but cached items return immediately, and photos already finished aren't re-locked.
    func start(items: [MediaItem]) {
        let photos = items.filter { $0.type == .image }
        let videos = items.filter { $0.type == .video }

        // Everything already hashed for this exact set — nothing to do.
        if isComplete && photosTotal == photos.count && videosTotal == videos.count { return }

        // Photos already fully done and unchanged — keep Duplicates unlocked; just (re)hash videos.
        let photosAlreadyDone = photosComplete && photos.count == photosTotal

        photosTotal = photos.count
        videosTotal = videos.count
        guard !(photos.isEmpty && videos.isEmpty) else { photosComplete = true; isComplete = true; return }
        guard !isRunning else { return }

        isRunning = true
        isComplete = false
        if !photosAlreadyDone { photosComplete = false }

        task = Task { [weak self] in
            guard let self else { return }

            // Phase 1 — photos (unlocks Duplicates).
            if !photosAlreadyDone {
                for (i, item) in photos.enumerated() {
                    if Task.isCancelled { self.isRunning = false; return }
                    _ = await self.hashStore.hash(for: item)   // cached hits return immediately
                    if i % 10 == 0 { self.photosDone = min(i + 1, self.photosTotal) }
                }
                self.photosDone = self.photosTotal
                self.photosComplete = true
                await self.hashStore.flush()
            }

            // Phase 2 — videos (Duplicates already usable; fills in video dupes).
            for (i, item) in videos.enumerated() {
                if Task.isCancelled { break }
                _ = await self.hashStore.hash(for: item)
                if i % 5 == 0 { self.videosDone = min(i + 1, self.videosTotal) }
            }
            await self.hashStore.flush()

            let cancelled = Task.isCancelled
            self.isRunning = false
            if !cancelled {
                self.videosDone = self.videosTotal
                self.isComplete = true
            }
        }
    }

    /// Stop the current pass (called when the app backgrounds). Progress persists in the hash store;
    /// resumes on the next `start`. Photos already finished stay finished (card stays unlocked).
    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }
}
