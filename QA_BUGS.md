# QA Bugs — cross-platform findings

Bugs found during iOS device testing (build 1→6, July 2026) that are **logic/behavioral**
issues likely to exist in the Android app too. Pure iOS/Swift-only defects (a Swift
`CheckedContinuation` double-resume crash, and a SwiftUI layout-driven thumbnail reload) are
**excluded** on purpose — they can't occur in the Android/Kotlin code.

Each item lists the symptom, the root cause in platform-neutral terms, and where to look in the
Android codebase.

---

## 1. Gallery thumbnails render blurry on large screens (tablet)
- **Symptom:** In the gallery grid, thumbnails are noticeably soft/blurry; opening the photo
  full-screen shows it sharp. Very visible on a tablet (large grid cells), fine on a phone.
- **Root cause:** The thumbnail request uses a **fixed pixel target** sized for a phone-sized
  cell. On a tablet the cell is physically much larger, so the fixed-size thumbnail is upscaled
  and blurs. The request size must be derived from the **actual cell size × display density**,
  not a constant.
- **Android check:** Confirm the thumbnail load (Glide/`override(...)` or equivalent) sizes to
  the real `ImageView`/cell dimensions rather than a hard-coded px. On large tablets or
  multi-column layouts a constant `override(width,height)` will look soft.

## 2. Sticky month header shows the *previous* month when a short month is opened
- **Symptom:** Open a month with only a few items (e.g. "Aug 2025", 2 photos). The photos shown
  are correct (Aug) and the bottom action bar correctly says "Hide Aug 2025", but the **sticky
  header at the top of the list shows the neighbouring month ("July 2025")**.
- **Root cause:** The "current month" for the sticky header was inferred purely from **scroll
  geometry** (which header has crossed the top edge). For a short month, the *next* month's
  header sits just below the top and gets mis-selected as the current month. The fix: when a
  month is explicitly **open/expanded**, the sticky header should name **that** month directly
  (the same source of truth the Hide bar uses), only falling back to scroll geometry when no
  month is open.
- **Android check:** Wherever the pinned/sticky header label is computed (the equivalent of the
  header decoration or the "current top group" logic in `GalleryAdapter`/RecyclerView). Ensure
  the currently-expanded month wins over a geometry guess.

## 3. "By City" (location) count is stale after deleting located photos
- **Symptom:** Home screen "By City" card shows e.g. "8 located". After deleting the geotagged
  photos, the card **still shows 8**, but tapping it correctly shows "No places found".
- **Root cause:** The Home count came from the **place cache's total entries**, which still
  include rows for photos that were deleted from the library. The detail screen filters entries
  to the **live photo set**, so the two disagree. The count must be intersected with the current
  live photo IDs (and/or the place cache pruned of deleted IDs).
- **Android check:** `PlaceStore`/`PlaceIndexer` located-count used by the Home card. Confirm it
  filters by currently-existing media IDs, matching what the By-City/Drill screen displays. This
  is almost certainly the same bug on Android since the store persists entries by id and isn't
  pruned on deletion.

## 4. "Scanning photos…" shown indefinitely when no photo has GPS
- **Symptom:** The "By City" card shows "Scanning photos…" forever on a library where **no
  photos have location metadata** — misleading, since nothing is actually still scanning.
- **Root cause:** The card only distinguished `count > 0` (show count) vs `count == 0` (show
  "Scanning…"). There was no "indexing finished with zero results" state. Fixed by tracking an
  **indexing-done** flag and showing "No location data" once the pass completes with 0 located.
- **Android check:** The Home location card's subtitle logic. Add a terminal "no location data"
  state distinct from the in-progress "scanning" state.

## 5. (Minor / UX parity) Help entry point discoverability
- **Symptom:** On iOS, Help ("How It Works") was initially reachable only *inside* Settings,
  whereas Android surfaces **Help + Settings together** in the overflow (three-dot) menu.
- **Resolution:** iOS now shows an overflow (•••) menu on the Home screen with **Help** and
  **Settings**, matching Android. Not a code bug — noted for parity.

---

### Excluded (iOS/Swift-only — do NOT apply to Android)
- **Crash entering a month:** an iOS Swift `withCheckedContinuation` was resumed more than once
  because the Photos framework's `.opportunistic` delivery calls its handler multiple times.
  Language/framework-specific; no Kotlin analogue.
- **Thumbnail flicker after opening a month:** a SwiftUI `GeometryReader`-keyed reload re-fired
  during the expand animation. UI-framework-specific regression, since fixed.
