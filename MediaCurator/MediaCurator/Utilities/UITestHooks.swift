import Foundation

/// Debug-only test scaffolding. In a Release/store build every flag below is a compile-time `false`,
/// so all `if UITestHooks.… { }` blocks (synthetic gallery data, PhotoKit bypasses, the auto-drive
/// drivers) are dead-code-eliminated and cannot run for real users.
///
/// Enabled only on the simulator via launch args, e.g.:
///   xcrun simctl launch <sim> com.anant.MediaCurator -uiGalleryScroll        # drive + scroll gallery
///   xcrun simctl launch <sim> com.anant.MediaCurator -uiGalleryScroll -uiCollapse   # + collapse (p2)
///   xcrun simctl launch <sim> com.anant.MediaCurator -uiTrash                # stage items, open Trash
/// Lets screen LAYOUT be screenshotted headlessly on a machine that can't tap the sim — see
/// PORTING_NOTES "Headless UI harness".
enum UITestHooks {
    #if DEBUG
    private static var args: Set<String> { Set(CommandLine.arguments) }
    /// Drive the gallery open + scroll deep.
    static var galleryScroll: Bool { args.contains("-uiGalleryScroll") }
    /// After scrolling, collapse the month (reproduces the p2 blank-after-collapse scenario).
    static var collapseAfterScroll: Bool { args.contains("-uiCollapse") }
    /// Stage a few items and open the Trash screen.
    static var trash: Bool { args.contains("-uiTrash") }
    /// Open the gallery via the "Free up space" path (Largest-overall sort).
    static var freeSpace: Bool { args.contains("-uiFreeSpace") }
    /// Open the Browse-by-location (cities) screen.
    static var place: Bool { args.contains("-uiPlace") }
    /// Open two months so the previous-month pill appears.
    static var prevMonth: Bool { args.contains("-uiPrevMonth") }
    /// Open a month, then scroll far past it into a LATER year — answers whether the pinned bar is
    /// positional (relabels to the year on screen) or frozen to whatever month is open.
    static var crossYear: Bool { args.contains("-uiCrossYear") }
    /// Open a month near the BOTTOM, then scroll UP above it — the open month is now BELOW the
    /// viewport. Checks the bar doesn't keep pinning it (the "Mar 2023 reappears at Sep 2024" bug).
    static var scrollUp: Bool { args.contains("-uiScrollUp") }
    /// Enter photo selection mode programmatically — isolates "does the state change pop the
    /// gallery?" from "does the long-press gesture pop it?", which a tap-less harness can't
    /// otherwise separate.
    static var select: Bool { args.contains("-uiSelect") }
    /// Any test mode: gates the synthetic data + PhotoKit bypasses (so nothing prompts).
    static var synthetic: Bool { galleryScroll || trash || freeSpace || place || prevMonth || select || crossYear || scrollUp }
    #else
    static let galleryScroll = false
    static let collapseAfterScroll = false
    static let trash = false
    static let freeSpace = false
    static let place = false
    static let prevMonth = false
    static let select = false
    static let crossYear = false
    static let scrollUp = false
    static let synthetic = false
    #endif
}
