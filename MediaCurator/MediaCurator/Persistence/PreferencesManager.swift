import Foundation

/// Wraps UserDefaults. Mirrors Android's `PreferencesManager`.
/// All keys kept identical to the Android side so backup JSON formats stay compatible.
final class PreferencesManager {

    private let defaults: UserDefaults
    private enum Key {
        static let doneMonths           = "done_months"
        static let sortMode             = "sort_mode"
        static let includePhoto         = "include_photo"
        static let includeVideo         = "include_video"
        static let includePdf           = "include_pdf"
        static let includeAudio         = "include_audio"
        static let expandedYears        = "expanded_years"
        static let expandedMonths       = "expanded_months"
        static let expandedSubGroups    = "expanded_subgroups"
        static let seenSubGroups        = "seen_subgroups"
        static let stagedForDeletion    = "staged_for_deletion"
        static let pdfContentSearch     = "pdf_content_search"
        static let photoDupDetection    = "photo_duplicate_detection"
        static let seenOnboarding       = "seen_onboarding"
        static let lastBatch            = "last_deleted_batch"
        static let hiddenRestoreOffered = "hidden_restore_offered"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Done months

    func markMonthDone(year: Int, month: Int) {
        var current = getDoneMonths()
        current.insert(Self.monthKey(year: year, month: month))
        defaults.set(Array(current), forKey: Key.doneMonths)
    }

    func unmarkMonthDone(year: Int, month: Int) {
        var current = getDoneMonths()
        current.remove(Self.monthKey(year: year, month: month))
        defaults.set(Array(current), forKey: Key.doneMonths)
    }

    func getDoneMonths() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.doneMonths) ?? [])
    }

    func setDoneMonths(_ months: Set<String>) {
        defaults.set(Array(months), forKey: Key.doneMonths)
    }

    func isMonthDone(year: Int, month: Int) -> Bool {
        getDoneMonths().contains(Self.monthKey(year: year, month: month))
    }

    // MARK: - Sort mode

    func saveSortMode(_ mode: SortMode) {
        defaults.set(mode.rawValue, forKey: Key.sortMode)
    }

    func getSortMode() -> SortMode {
        // Default to oldest-first — curation works through the library from the oldest
        // month forward (matches the Android default).
        guard let raw = defaults.string(forKey: Key.sortMode),
              let mode = SortMode(rawValue: raw) else { return .dateOldest }
        return mode
    }

    // MARK: - Type filters

    func saveIncludePhoto(_ v: Bool) { defaults.set(v, forKey: Key.includePhoto) }
    func isIncludePhoto() -> Bool    { defaults.object(forKey: Key.includePhoto) as? Bool ?? true }

    func saveIncludeVideo(_ v: Bool) { defaults.set(v, forKey: Key.includeVideo) }
    func isIncludeVideo() -> Bool    { defaults.object(forKey: Key.includeVideo) as? Bool ?? true }

    func saveIncludePdf(_ v: Bool)   { defaults.set(v, forKey: Key.includePdf) }
    func isIncludePdf() -> Bool      { defaults.object(forKey: Key.includePdf) as? Bool ?? true }

    func saveIncludeAudio(_ v: Bool) { defaults.set(v, forKey: Key.includeAudio) }
    func isIncludeAudio() -> Bool    { defaults.object(forKey: Key.includeAudio) as? Bool ?? true }

    // MARK: - Expansion state

    func saveExpandedYears(_ years: Set<Int>) {
        defaults.set(years.map { String($0) }, forKey: Key.expandedYears)
    }
    func getExpandedYears() -> Set<Int> {
        Set((defaults.stringArray(forKey: Key.expandedYears) ?? []).compactMap { Int($0) })
    }

    func saveExpandedMonths(_ months: Set<String>) {
        defaults.set(Array(months), forKey: Key.expandedMonths)
    }
    func getExpandedMonths() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.expandedMonths) ?? [])
    }

    func saveExpandedSubGroups(_ groups: Set<String>) {
        defaults.set(Array(groups), forKey: Key.expandedSubGroups)
    }
    func getExpandedSubGroups() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.expandedSubGroups) ?? [])
    }

    /// Sub-groups the user has opened at least once (ever). Grows only — never cleared on
    /// collapse — so "Hide Month" appears only after every sub-group has been reviewed,
    /// and that review survives across sessions. One entry per sub-group, e.g. "2024-03:cam".
    func saveSeenSubGroups(_ groups: Set<String>) {
        defaults.set(Array(groups), forKey: Key.seenSubGroups)
    }
    func getSeenSubGroups() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.seenSubGroups) ?? [])
    }

    // MARK: - Feature flags

    func isPdfContentSearchEnabled() -> Bool {
        defaults.object(forKey: Key.pdfContentSearch) as? Bool ?? true
    }
    func setPdfContentSearchEnabled(_ v: Bool) { defaults.set(v, forKey: Key.pdfContentSearch) }

    func isPhotoDuplicateDetectionEnabled() -> Bool {
        defaults.object(forKey: Key.photoDupDetection) as? Bool ?? true
    }
    func setPhotoDuplicateDetectionEnabled(_ v: Bool) { defaults.set(v, forKey: Key.photoDupDetection) }

    func hasSeenOnboarding() -> Bool { defaults.bool(forKey: Key.seenOnboarding) }
    func setSeenOnboarding()         { defaults.set(true, forKey: Key.seenOnboarding) }

    func wasHiddenRestoreOffered() -> Bool { defaults.bool(forKey: Key.hiddenRestoreOffered) }
    func setHiddenRestoreOffered()         { defaults.set(true, forKey: Key.hiddenRestoreOffered) }

    // MARK: - Last deleted batch (quick-undo)

    struct BatchEntry: Codable {
        let identifier: String  // PHAsset localIdentifier
        let size: Int64
    }

    func setLastDeletedBatch(_ items: [(identifier: String, size: Int64)]) {
        guard !items.isEmpty else { clearLastDeletedBatch(); return }
        let entries = items.map { BatchEntry(identifier: $0.identifier, size: $0.size) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Key.lastBatch)
        }
    }

    func getLastDeletedBatch() -> [(identifier: String, size: Int64)] {
        guard let data = defaults.data(forKey: Key.lastBatch),
              let entries = try? JSONDecoder().decode([BatchEntry].self, from: data)
        else { return [] }
        return entries.map { ($0.identifier, $0.size) }
    }

    func clearLastDeletedBatch() { defaults.removeObject(forKey: Key.lastBatch) }

    // MARK: - Helpers

    // MARK: - Trash (staged for deletion)

    /// PHAsset localIdentifiers the user has staged for deletion. The photos still live in
    /// the Photos library (hidden in our app) until the user commits the batch. Persisted so
    /// staging survives app restarts — nothing is ever deleted automatically.
    func getStagedForDeletion() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.stagedForDeletion) ?? [])
    }
    func setStagedForDeletion(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: Key.stagedForDeletion)
    }

    /// "YYYY-MM" key, e.g. "2024-03". Static so MonthGroup can call it without an instance.
    static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }
}
