import Foundation
import Photos
import Combine

/// Computes the home-screen summary state from the shared MediaCache.
/// Mirrors Android's `HomeViewModel` and `HomeState`.
struct HomeState {
    let summary: String
    let heroTitle: String
    let heroProgress: Int           // 0-100, or -1 to hide the bar
    let heroProgressLabel: String   // "" hides
    let heroCaption: String
    let resumeLabel: String
    let heroButton: String
    let resumeMonthKey: String?
    let dupSub: String
    let hiddenSub: String
    let trashSub: String
    let trashEmpty: Bool
    var placeCount: Int = 0
    /// True once the background place-indexing pass has finished, so the UI can distinguish
    /// "still scanning" from "finished, but no photos had location data".
    var placeIndexingDone: Bool = false
}

@MainActor
final class HomeViewModel: ObservableObject {

    @Published var state: HomeState? = nil
    @Published var isLoading = false

    private let repo  = MediaRepository()
    private let prefs = PreferencesManager()

    func load() {
        Task {
            isLoading = true
            defer { isLoading = false }

            // Request photo-library access up front (mirrors Android's Home permission gate).
            // If TCC already grants it, this returns the real status without prompting; if not,
            // it shows the system prompt. We proceed either way — an empty library renders the
            // "no media" state cleanly.
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            // Screenshot-test hook only: don't raise the (untappable) permission prompt on the sim.
            if status == .notDetermined && !UITestHooks.galleryScroll {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }

            let media    = await MediaCache.shared.get(repo: repo)
            let done     = prefs.getDoneMonths()
            let cal      = Calendar.current

            var byMonth: [String: Int] = [:]
            var totalSize: Int64 = 0
            for item in media {
                let y = cal.component(.year,  from: item.dateTaken)
                let m = cal.component(.month, from: item.dateTaken)
                let key = PreferencesManager.monthKey(year: y, month: m)
                byMonth[key, default: 0] += 1
                totalSize += item.size
            }

            let monthsOldest = byMonth.keys.sorted()
            let totalMonths  = monthsOldest.count
            let doneCount    = monthsOldest.filter { done.contains($0) }.count
            let oldestUncurated = monthsOldest.first { !done.contains($0) }
            // Resume target: the last month viewed if it's still visible (exists + not hidden);
            // otherwise the oldest un-curated month. "Pick up where you left off" (spec §3).
            let lastViewed   = prefs.getLastViewedMonth()
            let resumeKey: String? = {
                if let lv = lastViewed, byMonth[lv] != nil, !done.contains(lv) { return lv }
                return oldestUncurated
            }()
            let hiddenItems  = monthsOldest.filter { done.contains($0) }.reduce(0) { $0 + (byMonth[$1] ?? 0) }

            // Trash = items staged for deletion (reconciled against the live library).
            let liveIDs      = Set(media.map(\.id))
            let staged       = prefs.getStagedForDeletion().intersection(liveIDs)
            let trashItems   = media.filter { staged.contains($0.id) }
            let trashBytes   = trashItems.reduce(0) { $0 + $1.size }

            await PlaceStore.shared.ensureLoaded()
            let placeCount = await PlaceStore.shared.locatedCount(validIDs: liveIDs)

            var built = buildState(
                total: media.count,
                size: totalSize,
                hidden: hiddenItems,
                totalMonths: totalMonths,
                doneMonths: doneCount,
                resumeKey: resumeKey,
                trashCount: trashItems.count,
                trashBytes: trashBytes
            )
            built.placeCount = placeCount
            state = built

            // Continuously hash photos+videos in the background so the Duplicates screen is instant.
            // Serial + cancel-on-background (see HashingCoordinator) keeps it watchdog-safe.
            // (Skipped under the screenshot-test flag — it would touch PhotoKit and prompt.)
            if prefs.isPhotoDuplicateDetectionEnabled() && !UITestHooks.galleryScroll {
                HashingCoordinator.shared.start(items: media)
            }

            // Kick place indexing in the background (offline reverse-geocoding, spec §7) so the
            // location cards light up. Refresh the count when it finishes.
            if prefs.isPlaceSearchEnabled() && !UITestHooks.galleryScroll {
                Task.detached(priority: .background) {
                    _ = await PlaceIndexer.shared.index(media) { _, _ in }
                    // Count only located photos still in the live library (matches "By City").
                    let n = await PlaceStore.shared.locatedCount(validIDs: Set(media.map(\.id)))
                    await MainActor.run {
                        if var s = self.state {
                            s.placeCount = n
                            s.placeIndexingDone = true
                            self.state = s
                        }
                    }
                }
            } else {
                // Place search is off — not "scanning", just unavailable.
                built.placeIndexingDone = true
                state = built
            }
        }
    }

    private func buildState(
        total: Int,
        size: Int64,
        hidden: Int,
        totalMonths: Int,
        doneMonths: Int,
        resumeKey: String?,
        trashCount: Int,
        trashBytes: Int64
    ) -> HomeState {
        let summary = total == 0
            ? "No media found"
            : "\(Formatters.countShort(total)) items · \(Formatters.bytes(size)) · \(Formatters.countShort(hidden)) reviewed"

        let pct = totalMonths > 0 ? doneMonths * 100 / totalMonths : 0

        var title         = "Continue curating"
        var progress      = pct
        var progressLabel = "\(pct)% curated"
        var caption       = "Pick up at"
        var resumeLabel   = Formatters.monthLabel(from: resumeKey ?? "")
        var button        = "Resume"

        switch true {
        case total == 0:
            title = "No media yet"; progress = -1; progressLabel = ""
            caption = ""; resumeLabel = "Add photos to get started"; button = "Browse photos"
        case doneMonths == 0:
            title = "Start curating"; progress = -1; progressLabel = ""
            caption = "Begin at"; button = "Start"
        case resumeKey == nil:
            title = "All caught up"; progress = 100; progressLabel = "100% curated"
            caption = ""; resumeLabel = "Everything reviewed"; button = "Browse all"
        default:
            break
        }

        return HomeState(
            summary: summary,
            heroTitle: title,
            heroProgress: progress,
            heroProgressLabel: progressLabel,
            heroCaption: caption,
            resumeLabel: resumeLabel,
            heroButton: button,
            resumeMonthKey: resumeKey,
            dupSub: "Not scanned yet",
            hiddenSub: hidden == 0 ? "Nothing hidden yet" : "\(Formatters.countShort(hidden)) hidden",
            trashSub: trashCount == 0 ? "0 items"
                : "\(Formatters.countShort(trashCount)) · \(Formatters.bytes(trashBytes))",
            trashEmpty: trashCount == 0
        )
    }
}
