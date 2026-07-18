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
    /// Any test mode: gates the synthetic data + PhotoKit bypasses (so nothing prompts).
    static var synthetic: Bool { galleryScroll || trash || freeSpace || place }
    #else
    static let galleryScroll = false
    static let collapseAfterScroll = false
    static let trash = false
    static let freeSpace = false
    static let place = false
    static let synthetic = false
    #endif
}
