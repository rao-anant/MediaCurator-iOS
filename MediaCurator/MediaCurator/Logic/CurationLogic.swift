import Foundation

/// Pure, platform-independent curation logic for the "Hide month" flow.
/// Mirrors Android's `CurationLogicTest.kt`; the behavioral source of truth is
/// `../MediaCurator-android/docs/CURATION_REGRESSION_TESTS.md`. Test IDs (WL-*, HB-*)
/// map to cases there and in MediaCuratorTests.

// MARK: - Walk-through gate (WalkLatch)

/// Tracks whether the user has "walked through" the open month — seen its header (top) and
/// then its footer (bottom), with the footer only counting once the header has been seen.
/// See CURATION_REGRESSION_TESTS §1.
struct WalkLatch {
    private var openMonth: String? = nil
    private var seenHeader = false
    private var seenFooter = false
    private var lastLength: Int? = nil
    private(set) var reached: Set<String> = []

    /// A month was just tapped open — begin a fresh walk (nothing seen) and drop its reached mark.
    /// "Header seen" is NEVER assumed here; it must be credited from a real observation.
    mutating func opened(_ month: String) {
        openMonth = month
        seenHeader = false
        seenFooter = false
        lastLength = nil
        reached.remove(month)
    }

    /// Recompute from the current viewport. Call only when the list is settled (see G-1).
    /// - headerPos/footerPos: the open month's header/footer row indices.
    /// - first/last: indices of the first/last visible rows.
    /// - renderedLength: the open month's current rendered row count (changes when a sub-group
    ///   expands/collapses), used to re-arm the gate.
    mutating func viewportEvaluated(openMonth month: String,
                                    headerPos: Int, footerPos: Int,
                                    first: Int, last: Int,
                                    renderedLength: Int) {
        // Re-arm on month change or length change: clear both flags and drop the reached mark;
        // the top must be (re-)seen from an actual observation before the footer can count.
        if month != openMonth || renderedLength != lastLength {
            openMonth = month
            seenHeader = false
            seenFooter = false
            lastLength = renderedLength
            reached.remove(month)
        }
        if first <= headerPos { seenHeader = true }
        if last >= footerPos && seenHeader { seenFooter = true }
        if seenHeader && seenFooter { reached.insert(month) }
    }

    func isReached(_ month: String) -> Bool { reached.contains(month) }

    /// Curation-progress reset — clear all walk state (WL-6).
    mutating func reset() {
        openMonth = nil
        seenHeader = false
        seenFooter = false
        lastLength = nil
        reached.removeAll()
    }
}

// MARK: - Revisit shortcut (WalkedMonthRule)

/// Once a month has been fully walked, its item count is remembered; on a later visit the walk
/// is skipped unless new items appeared. See CURATION_REGRESSION_TESTS §1 (revisit shortcut).
enum WalkedMonthRule {
    /// A previously walked month with `walkedCount` items still counts as walked if the current
    /// count hasn't grown (deletions are fine; only new photos re-require the walk).
    static func stillWalked(walkedCount: Int, currentCount: Int) -> Bool {
        currentCount <= walkedCount
    }
}

// MARK: - Bottom-bar decision (HideBarDecision)

/// The one bar state to show, from four booleans. See CURATION_REGRESSION_TESTS §2 (HB-1…HB-6).
enum HideBarState: Equatable {
    case hide          // green "Hide {Month}"
    case scrollTeaser  // "Delete junk… hide {Month} at the end"
    case reviewHint    // "Also open WhatsApp…" / "Turn on all filters…"
    case none
}

enum HideBarDecision {
    /// - showHideButton: month fully reviewed (per sub-group × type).
    /// - reachedEnd: month walked this session, or the revisit shortcut applies.
    /// - scrollHintRetired: user hid their first month or dismissed the teaser.
    /// - hasReviewHint: there's a still-unreviewed section worth nudging toward.
    static func decide(showHideButton: Bool,
                       reachedEnd: Bool,
                       scrollHintRetired: Bool,
                       hasReviewHint: Bool) -> HideBarState {
        if showHideButton && reachedEnd { return .hide }                         // HB-1, HB-6
        if showHideButton && !reachedEnd && !scrollHintRetired { return .scrollTeaser } // HB-2
        if showHideButton && !reachedEnd && scrollHintRetired { return .none }    // HB-3
        if !showHideButton && !scrollHintRetired && hasReviewHint { return .reviewHint } // HB-4
        return .none                                                             // HB-5
    }
}
