import Testing
import Foundation
@testable import MediaCurator

/// Ports the Android CurationLogicTest / CURATION_REGRESSION_TESTS.md cases (WL-*, HB-*).
struct CurationLogicTests {

    // Helper: a full walk observation (header at top, footer on screen).
    private func fitsOnScreen() -> (headerPos: Int, footerPos: Int, first: Int, last: Int, len: Int) {
        (headerPos: 0, footerPos: 3, first: 0, last: 5, len: 4)
    }

    // MARK: - WalkLatch

    @Test func WL_1_monthFitsReachedImmediately() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        #expect(w.isReached("A"))
    }

    @Test func WL_2_longMonthNeedsScroll() {
        var w = WalkLatch()
        w.opened("A")
        // Opened at top, footer far below (not visible).
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 100, first: 0, last: 10, renderedLength: 101)
        #expect(!w.isReached("A"))
        // User scrolls until footer visible.
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 100, first: 92, last: 101, renderedLength: 101)
        #expect(w.isReached("A"))
    }

    @Test func WL_3_openingLongMonthBDoesNotInheritReached() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        #expect(w.isReached("A"))
        // Open long month B, lands at its top, footer far below.
        w.opened("B")
        w.viewportEvaluated(openMonth: "B", headerPos: 10, footerPos: 120, first: 10, last: 20, renderedLength: 110)
        #expect(!w.isReached("B"))
        #expect(w.isReached("A"))   // A stays reached independently
    }

    @Test func WL_3b_shortMonthLandingOnFooterNotReached() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        #expect(w.isReached("A"))
        // Open short month B that lands showing its OWN footer (header never at top).
        w.opened("B")
        w.viewportEvaluated(openMonth: "B", headerPos: 10, footerPos: 14, first: 11, last: 14, renderedLength: 5)
        #expect(!w.isReached("B"))   // the real-device bug: must NOT jump straight to Hide
    }

    @Test func WL_4_lengthChangeClearsReached() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        #expect(w.isReached("A"))
        // Sub-group expands (length changes), viewport mid-month.
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 8, first: 3, last: 6, renderedLength: 9)
        #expect(!w.isReached("A"))
    }

    @Test func WL_5_afterLengthChangeFooterOnlyNotReached() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        // Length change, then only footer visible (top never re-seen).
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 8, first: 4, last: 8, renderedLength: 9)
        #expect(!w.isReached("A"))
    }

    @Test func WL_6_resetClearsAll() {
        var w = WalkLatch()
        w.opened("A")
        w.viewportEvaluated(openMonth: "A", headerPos: 0, footerPos: 3, first: 0, last: 5, renderedLength: 4)
        #expect(w.isReached("A"))
        w.reset()
        #expect(!w.isReached("A"))
    }

    // MARK: - Revisit shortcut

    @Test func revisit_unchangedStillWalked() {
        #expect(WalkedMonthRule.stillWalked(walkedCount: 50, currentCount: 50))
    }
    @Test func revisit_fewerStillWalked() {
        #expect(WalkedMonthRule.stillWalked(walkedCount: 50, currentCount: 47))
    }
    @Test func revisit_moreRequiresWalk() {
        #expect(!WalkedMonthRule.stillWalked(walkedCount: 50, currentCount: 53))
    }

    // MARK: - HideBarDecision

    @Test func HB_1_reviewedAndReached_hide() {
        #expect(HideBarDecision.decide(showHideButton: true, reachedEnd: true,
                                       scrollHintRetired: false, hasReviewHint: false) == .hide)
    }
    @Test func HB_2_reviewedNotReached_teaser() {
        #expect(HideBarDecision.decide(showHideButton: true, reachedEnd: false,
                                       scrollHintRetired: false, hasReviewHint: false) == .scrollTeaser)
    }
    @Test func HB_3_reviewedNotReachedRetired_none() {
        #expect(HideBarDecision.decide(showHideButton: true, reachedEnd: false,
                                       scrollHintRetired: true, hasReviewHint: false) == .none)
    }
    @Test func HB_4_notReviewedHasHint_reviewHint() {
        #expect(HideBarDecision.decide(showHideButton: false, reachedEnd: false,
                                       scrollHintRetired: false, hasReviewHint: true) == .reviewHint)
    }
    @Test func HB_5_notReviewedNoHint_none() {
        #expect(HideBarDecision.decide(showHideButton: false, reachedEnd: false,
                                       scrollHintRetired: false, hasReviewHint: false) == .none)
    }
    @Test func HB_6_retiredTeaserNeverBlocksHide() {
        #expect(HideBarDecision.decide(showHideButton: true, reachedEnd: true,
                                       scrollHintRetired: true, hasReviewHint: false) == .hide)
    }

    // MARK: - Reset coverage (§4)

    @Test func resetClearsCurationKeysOnly() {
        let defaults = UserDefaults(suiteName: "reset-test-\(UUID().uuidString)")!
        let prefs = PreferencesManager(defaults: defaults)

        // Seed curation state (must be cleared) …
        prefs.markMonthDone(year: 2024, month: 3)
        prefs.saveSeenSubGroups(["2024-03:cam:image"])
        prefs.setWalkedCount(month: "2024-03", count: 10)
        prefs.setScrollHintRetired()
        prefs.setLastViewedMonth("2024-03")
        prefs.saveExpandedYears([2024])
        // … and non-curation state (must survive).
        prefs.saveSortMode(SortMode.dateNewest)
        prefs.saveIncludeVideo(false)
        prefs.setLastDeletedBatch([("id-1", 123)])

        prefs.resetCurationProgress()

        // Cleared:
        #expect(prefs.getDoneMonths().isEmpty)
        #expect(prefs.getSeenSubGroups().isEmpty)
        #expect(prefs.getWalkedCounts().isEmpty)
        #expect(!prefs.isScrollHintRetired())
        #expect(prefs.getLastViewedMonth() == nil)
        #expect(prefs.getExpandedYears().isEmpty)
        // Preserved:
        #expect(prefs.getSortMode() == SortMode.dateNewest)
        #expect(prefs.isIncludeVideo() == false)
        #expect(prefs.getLastDeletedBatch().count == 1)
    }
}
