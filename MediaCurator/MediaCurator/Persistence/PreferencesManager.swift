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
        static let lastHiddenMonth      = "last_hidden_month"
        static let scrollHintRetired    = "scroll_hint_retired"
        static let walkedCounts         = "walked_month_counts"
        static let lastViewedMonth      = "last_viewed_month"
        static let hideCoachMarkShown   = "hide_coach_mark_shown"
        static let demoOptedOut         = "demo_opted_out"
        static let installInitialized   = "install_initialized"
        static let pdfContentSearch     = "pdf_content_search"
        static let photoDupDetection    = "photo_duplicate_detection"
        static let placeSearch          = "place_search"
        static let seenOnboarding       = "seen_onboarding"
        static let lastBatch            = "last_deleted_batch"
        static let hiddenRestoreOffered = "hidden_restore_offered"
        static let placeIntroShown      = "place_intro_shown"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Done months

    func markMonthDone(year: Int, month: Int) {
        var current = getDoneMonths()
        current.insert(Self.monthKey(year: year, month: month))
        defaults.set(Array(current), forKey: Key.doneMonths)
        // Remember the most recently hidden month so the Hidden screen can jump to it.
        defaults.set(Self.monthKey(year: year, month: month), forKey: Key.lastHiddenMonth)
    }

    /// The most recently hidden month key, if it's still hidden; else nil.
    func getLastHiddenMonth() -> String? {
        guard let key = defaults.string(forKey: Key.lastHiddenMonth),
              getDoneMonths().contains(key) else { return nil }
        return key
    }

    // MARK: - Curation coaching / walk-through (spec §3, CURATION_REGRESSION_TESTS)

    /// True once the user has hidden their first month or dismissed a hint — after which
    /// reviewed months jump straight to Hide with no teaser/coaching.
    func isScrollHintRetired() -> Bool { defaults.bool(forKey: Key.scrollHintRetired) }
    func setScrollHintRetired() { defaults.set(true, forKey: Key.scrollHintRetired) }

    /// One-time "browse by place" intro banner (spec §7 PU-9) — shown once, ever.
    func isPlaceIntroShown() -> Bool { defaults.bool(forKey: Key.placeIntroShown) }
    func setPlaceIntroShown() { defaults.set(true, forKey: Key.placeIntroShown) }

    /// Per-month item count captured when a month was fully walked (revisit shortcut).
    func getWalkedCounts() -> [String: Int] {
        (defaults.dictionary(forKey: Key.walkedCounts) as? [String: Int]) ?? [:]
    }
    func setWalkedCount(month: String, count: Int) {
        var m = getWalkedCounts(); m[month] = count
        defaults.set(m, forKey: Key.walkedCounts)
    }

    /// The month the user was last viewing in the gallery — the "pick up where you left off"
    /// resume target (spec §3 Landing position).
    func getLastViewedMonth() -> String? { defaults.string(forKey: Key.lastViewedMonth) }
    func setLastViewedMonth(_ key: String?) {
        if let key { defaults.set(key, forKey: Key.lastViewedMonth) }
        else { defaults.removeObject(forKey: Key.lastViewedMonth) }
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

    /// Place search (offline reverse-geocoding, spec §7) — default ON.
    func isPlaceSearchEnabled() -> Bool { defaults.object(forKey: Key.placeSearch) as? Bool ?? true }
    func setPlaceSearchEnabled(_ v: Bool) { defaults.set(v, forKey: Key.placeSearch) }

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

    // MARK: - First-run demo (spec §13)

    // MARK: - Reinstall-safe durable backup (keychain — survives uninstall, no iCloud entitlement)

    /// Small, per-device state mirrored to the keychain so it survives an app reinstall: hidden
    /// months, the coaching flags, and the lifetime "cleaned up" totals. NOT the demo opt-out
    /// (a separate set-once marker below) and NOT the place index (that re-scans from EXIF).
    private static let durableKeys: [String] = [
        Key.doneMonths, Key.scrollHintRetired, Key.hideCoachMarkShown,
        Key.placeIntroShown, Key.seenOnboarding,
        "stats_total_deleted", "stats_total_bytes_freed",   // DeletionStatsStore
    ]
    private static let durableAccount = "durable_state_v1"
    private static let demoOptOutAccount = "demo_opted_out_v1"

    func isDemoOptedOut() -> Bool { defaults.bool(forKey: Key.demoOptedOut) }

    /// Opt out of the first-run demo. Writes the per-install prefs flag AND a durable, set-once
    /// keychain marker so the opt-out survives uninstall/reinstall (FR-2). Reset never clears the
    /// marker (FR-3 governs only the current install's prefs flag).
    func setDemoOptedOut(_ v: Bool) {
        defaults.set(v, forKey: Key.demoOptedOut)
        if v { KeychainStore.set(Data([1]), account: Self.demoOptOutAccount) }
    }

    /// Snapshot the durable keys to the keychain. Cheap; called when the app backgrounds and
    /// after a curation reset, so the keychain always reflects the latest state.
    func backupDurableState() {
        var dict: [String: Any] = [:]
        for key in Self.durableKeys where defaults.object(forKey: key) != nil {
            dict[key] = defaults.object(forKey: key)
        }
        if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
            KeychainStore.set(data, account: Self.durableAccount)
        }
    }

    /// Call once at launch. On a FRESH install (never initialized), restore the durable state and
    /// re-apply the demo opt-out from the keychain (FR-2). After a reset (already initialized),
    /// nothing is restored, so reset governs the current install (FR-3).
    func restoreDurableStateIfFreshInstall() {
        guard !defaults.bool(forKey: Key.installInitialized) else { return }
        if let data = KeychainStore.get(account: Self.durableAccount),
           let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            for (k, v) in dict { defaults.set(v, forKey: k) }
        }
        if KeychainStore.get(account: Self.demoOptOutAccount) != nil {
            defaults.set(true, forKey: Key.demoOptedOut)
        }
        defaults.set(true, forKey: Key.installInitialized)
    }

    func wasHideCoachMarkShown() -> Bool { defaults.bool(forKey: Key.hideCoachMarkShown) }
    func setHideCoachMarkShown() { defaults.set(true, forKey: Key.hideCoachMarkShown) }

    // MARK: - Reset curation progress (spec §4)

    /// Clears exactly the curation keys and nothing else. After this, hidden months reappear
    /// un-hidden and reviewed/walked months must be reviewed & scrolled again. Deliberately
    /// does NOT touch: sort mode, media-type filters, PDF/dup toggles, the hidden-restore
    /// prompt flag, or the last-deleted batch (quick-undo).
    func resetCurationProgress() {
        for key in [
            Key.doneMonths, Key.seenSubGroups, Key.walkedCounts, Key.scrollHintRetired,
            Key.hideCoachMarkShown, Key.demoOptedOut, Key.lastHiddenMonth, Key.lastViewedMonth,
            Key.expandedYears, Key.expandedMonths, Key.expandedSubGroups,
        ] {
            defaults.removeObject(forKey: key)
        }
        // Re-snapshot so a later reinstall restores the *reset* state, not the old hidden months.
        backupDurableState()
    }

    /// "YYYY-MM" key, e.g. "2024-03". Static so MonthGroup can call it without an instance.
    static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }
}
