import Foundation

/// Debug-only test scaffolding. In a Release/store build `galleryScroll` is a compile-time `false`,
/// so every `if UITestHooks.galleryScroll { … }` block (synthetic gallery data, PhotoKit bypasses,
/// the auto-drive-and-scroll driver) is dead-code-eliminated and cannot run for real users.
///
/// Enabled only on the simulator by launching with `-uiGalleryScroll`, e.g.:
///   xcrun simctl launch <sim> com.anant.MediaCurator -uiGalleryScroll
/// It lets the gallery LAYOUT (sticky headers, month tree, scroll landing) be screenshotted
/// headlessly on a machine that can't tap the simulator — see PORTING_NOTES "Headless UI harness".
enum UITestHooks {
    #if DEBUG
    static var galleryScroll: Bool { CommandLine.arguments.contains("-uiGalleryScroll") }
    /// After driving April open + scrolling deep, collapse April from that scrolled position —
    /// reproduces the "blank screen after collapsing a scrolled month" (p2) bug for a screenshot.
    static var collapseAfterScroll: Bool { CommandLine.arguments.contains("-uiCollapse") }
    #else
    static let galleryScroll = false
    static let collapseAfterScroll = false
    #endif
}
