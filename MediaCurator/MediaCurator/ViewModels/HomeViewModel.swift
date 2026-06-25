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
            if status == .notDetermined {
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
            let resumeKey    = monthsOldest.first { !done.contains($0) }
            let hiddenItems  = monthsOldest.filter { done.contains($0) }.reduce(0) { $0 + (byMonth[$1] ?? 0) }

            state = buildState(
                total: media.count,
                size: totalSize,
                hidden: hiddenItems,
                totalMonths: totalMonths,
                doneMonths: doneCount,
                resumeKey: resumeKey
            )
        }
    }

    private func buildState(
        total: Int,
        size: Int64,
        hidden: Int,
        totalMonths: Int,
        doneMonths: Int,
        resumeKey: String?
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
            caption = ""; resumeLabel = "Add photos to get started"; button = "Open gallery"
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
            trashSub: "0 items",
            trashEmpty: true
        )
    }
}
