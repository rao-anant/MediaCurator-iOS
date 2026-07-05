import Foundation
import Combine

/// Lists the months the user has marked done ("hidden" from the gallery) so they can be
/// reviewed and un-hidden. Mirrors Android's `HiddenViewModel` / `HiddenActivity`.
@MainActor
final class HiddenViewModel: ObservableObject {

    /// One row per done month, newest first.
    struct DoneMonth: Identifiable {
        let key: String          // "YYYY-MM"
        let label: String        // "March 2024"
        let count: Int
        let totalBytes: Int64
        var id: String { key }
    }

    @Published var months: [DoneMonth] = []
    @Published var isLoading = false

    private var allMedia: [MediaItem] = []

    /// Items in a hidden month, newest first — for the preview grid.
    func items(forMonth key: String) -> [MediaItem] {
        let cal = Calendar.current
        return allMedia.filter {
            let y = cal.component(.year, from: $0.dateTaken)
            let m = cal.component(.month, from: $0.dateTaken)
            return PreferencesManager.monthKey(year: y, month: m) == key
        }.sorted { $0.dateTaken > $1.dateTaken }
    }

    /// Most recently hidden month key (if still hidden) — the Hidden screen jumps to it.
    var lastHiddenMonth: String? { prefs.getLastHiddenMonth() }

    /// Distinct years that have hidden months, newest first.
    var years: [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for m in months {
            let y = Int(m.key.prefix(4)) ?? 0
            if seen.insert(y).inserted { result.append(y) }
        }
        return result.sorted(by: >)
    }

    /// Hidden months within a given year, newest first.
    func months(in year: Int) -> [DoneMonth] {
        months.filter { Int($0.key.prefix(4)) == year }
    }

    private let repo  = MediaRepository()
    private let prefs = PreferencesManager()

    func load() {
        Task {
            isLoading = true
            defer { isLoading = false }

            let media = await MediaCache.shared.get(repo: repo)
            allMedia = media
            let done  = prefs.getDoneMonths()
            let cal   = Calendar.current

            // Tally count + bytes per done month from the shared media scan.
            var counts: [String: (count: Int, bytes: Int64)] = [:]
            for item in media {
                let y = cal.component(.year,  from: item.dateTaken)
                let m = cal.component(.month, from: item.dateTaken)
                let key = PreferencesManager.monthKey(year: y, month: m)
                guard done.contains(key) else { continue }
                let cur = counts[key] ?? (0, 0)
                counts[key] = (cur.count + 1, cur.bytes + item.size)
            }

            // Include done months even if they currently have zero matching items.
            months = done.sorted(by: >).map { key in
                let tally = counts[key] ?? (0, 0)
                return DoneMonth(
                    key: key,
                    label: Formatters.monthLabel(from: key),
                    count: tally.count,
                    totalBytes: tally.bytes
                )
            }
        }
    }

    func unhide(_ key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        prefs.unmarkMonthDone(year: y, month: m)
        months.removeAll { $0.key == key }
    }
}
