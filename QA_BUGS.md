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

## 6. (iOS-only) Year header rendered twice — bare pinned row above the real one (ph8)
- **Symptom:** With a month open, the year appeared on two consecutive rows: a bare `2024` (no
  counts) directly above the real `2024  104  4.2 MB` row. Android shows one row, with details.
- **Root cause:** The pinned sticky bar had a "pin only while the real in-list row is off screen"
  rule on its **month** and **sub-group** rows (added when "April 2024 appears twice" was fixed) but
  never on its **year** row. `stickyYear` short-circuited on `openMonthKey` and returned the year
  unconditionally, so opening any month pinned a year stand-in even with the real row on screen.
- **Fix:** Split into `stickyYearCandidate` (which year — still ungated, `stickyMonthLabel` needs it
  as a lookup key) and `stickyYear` (whether to pin — nil when the real `Y:` row reports y > 0).
- **Android check:** none needed; Android renders one year row correctly. iOS-only regression.
- **Follow-up (ph10/ph11):** with the duplicate gone, the remaining difference between the two
  states was that the *pinned* year row carried no count/size, so the figures appeared to vanish
  on scroll. Android's sticky year row shows them (`tvStickyYearStats`); iOS now does too, on one
  line to keep the bar slim. Also made all three pinned rows fully opaque — at `opacity(0.96)`
  the real row ghosted through the bar as it scrolled underneath.

## 7. (iOS-only) Blank screen after collapsing a scrolled-into month (p2)
- **Symptom:** Open a month, scroll deep into its photos, collapse it → the whole gallery goes
  blank below the sort bar. Reported on device for the whole port; never reproduced headlessly
  until now because it is **sort-dependent**.
- **Trigger:** it only happens when the collapsed month is near the BOTTOM of the list, so after
  collapse there isn't a screenful of content below it. Under the default "Oldest first" the opened
  month (2024/April in the test data) is near the TOP, so it never showed; under "Most items per
  month" (years descending → 2024 last → April near the end) it reproduces every time.
- **Root cause:** collapsing removes the month's photos, leaving the ScrollView scrolled far PAST
  the new, shorter content. The recovery `scrollTo("month-<key>")` can't fix it because the
  LazyVStack has dropped that row (it's far above the blank viewport and not instantiated), so
  `scrollTo` to it is a no-op — the view stays blank. This is a SwiftUI ScrollViewReader limitation:
  it can't reliably scroll to a non-instantiated lazy row.
- **Fix:** on collapse, first `scrollTo("gallery-top")` — a non-lazy anchor OUTSIDE the LazyVStack,
  so it's always instantiated and reliably pulls the viewport back into the content — then scroll to
  the collapsed month (gentle / nil anchor = minimum scroll, so it can't re-overshoot). Two-stage,
  in `GalleryView`'s `scrollRequest` handler, gated on the new `ScrollRequest.gentle` flag.
- **Android check:** none — Android's `scrollToPositionWithOffset(pos, offset)` scrolls by index and
  handles non-instantiated rows, so RecyclerView never had this. iOS-only.

---

### Excluded (iOS/Swift-only — do NOT apply to Android)
- **Crash entering a month:** an iOS Swift `withCheckedContinuation` was resumed more than once
  because the Photos framework's `.opportunistic` delivery calls its handler multiple times.
  Language/framework-specific; no Kotlin analogue.
- **Thumbnail flicker after opening a month:** a SwiftUI `GeometryReader`-keyed reload re-fired
  during the expand animation. UI-framework-specific regression, since fixed.
