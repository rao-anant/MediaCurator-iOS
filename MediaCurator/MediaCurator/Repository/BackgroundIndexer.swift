import Foundation
import BackgroundTasks

/// Lets iOS finish **place (geo) indexing** while the app is closed, via the Background Tasks
/// framework. iOS runs the task opportunistically when the device is idle and on power (typically
/// overnight), so a large library can finish locating without the user keeping the app open. It's
/// best-effort — the OS decides when — and progress is always resumable, so a partial run just
/// continues next time (foreground or background).
///
/// Only geo indexing runs here (it's light: a bulk GPS read + k-d lookups). Hashing is heavy and
/// user-initiated (Duplicates screen), so it's deliberately not run in the background.
///
/// Requires (set via the Background Modes capability + Info.plist): `UIBackgroundModes: [processing]`
/// and this id in `BGTaskSchedulerPermittedIdentifiers`. No entitlement / App-ID capability.
enum BackgroundIndexer {
    static let taskID = "com.anant.MediaCurator.indexing"

    /// Register the handler once, early in launch (before the app finishes launching).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
    }

    /// Ask iOS to run indexing later, when the device is idle and on power. Call when backgrounding.
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskID)
        request.requiresExternalPower = true          // don't spend the user's battery
        request.requiresNetworkConnectivity = false   // fully offline
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask) {
        // Re-submit so any remaining work continues in a later window.
        schedule()

        let work = Task {
            let media = await MediaCache.shared.get(repo: MediaRepository())
            // Skips already-located photos and flushes progress every 50, so cancellation on
            // expiry loses nothing.
            _ = await PlaceIndexer.shared.index(media) { _, _ in }
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        // iOS gives limited time; if it runs out, cancel — PlaceIndexer checks Task.isCancelled
        // between items and its flushed progress persists.
        task.expirationHandler = { work.cancel() }
    }
}
