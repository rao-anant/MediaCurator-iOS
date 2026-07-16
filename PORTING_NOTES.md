# MediaCurator iOS — Porting Progress

Living handoff doc for the Android → iOS port. Read this first when resuming.
Last updated: 2026-07-15.

---

## TestFlight device-QA build log (b18–b24)

On-device testing (real iPhone + iPad, internal TestFlight) surfaced a run of fixes after the
first TestFlight builds. App name is **GalleryCurator**; bundle id stays `com.anant.MediaCurator`;
paid team `4AK585R8JQ`. Signing/upload is fully headless (see the TestFlight section below).

- **b21** — background-finish place indexing via `BGProcessingTask` (see PARITY row).
- **b22** — fixed a **backgrounding crash**: `0x8BADF00D` scene-update watchdog. Full-library scans
  called `PHAssetResource.assetResources(for:)` per asset (for size/filename); at library scale this
  saturates PhotoKit's single CoreData context and, on backgrounding, blocks the main thread past the
  10 s watchdog. Fix: `AssetMetaStore` caches per-asset size/filename so re-scans skip the lookup for
  known assets. Also: empty-trash no longer forces a full rescan (`MediaCache.remove(ids:)`), Stats
  reads lifetime totals before the scan (no 0-flash), video-only grid uses 3 tiles, and the viewer
  pages the whole flat list in "Largest files" sort (month-scoping only applies to month-grouped sorts).
- **b23** — **Duplicate finder**: the library fetch deduped by `(displayName, size)`, dropping one of
  every exact-duplicate pair before detection. Now dedupes by `localIdentifier`. (Cross-platform — see
  PARITY; Android has the same `distinctBy`.) Video-only tile count keyed off displayed content, not the
  include flags. Gallery scroll: measure the floating sticky bar and land expand targets *below* it;
  scroll the just-collapsed month/year back into view; close an open month when its year collapses.
  Baked `ITSAppUsesNonExemptEncryption = NO` into Info.plist so builds skip the Missing-Compliance gate.
- **b24** — sub-group/year header rows are fully tappable (whole-row `contentShape`, not a `Button`
  that missed the chevron); only month-*open* lands below the sticky bar — collapse and year-open land
  at the true top so the sticky shows the row acted on.

Parked: continuous background hashing (#6 — do carefully, folded into the charging-idle background
task, only after the crash fix is confirmed stable); App Store screenshots + submission.

---

## Where things stand

The iOS app is **no longer a placeholder** — the first vertical slice (the Gallery
end-to-end) has been written and **compiles cleanly** for the iOS Simulator.

Xcode project lives at:
```
MediaCurator-iOS/MediaCurator/          ← Xcode project root
├── MediaCurator.xcodeproj
├── MediaCurator/                        ← source root (all our Swift files)
├── MediaCuratorTests/
└── MediaCuratorUITests/
```

Build command that works (simulator, no signing needed):
```bash
cd MediaCurator-iOS/MediaCurator
xcodebuild -scheme MediaCurator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```
Current status: **BUILD SUCCEEDED.**

---

## Target & architecture decisions

- **iOS 16 minimum** (`IPHONEOS_DEPLOYMENT_TARGET = 16.0`). Chosen for broad install
  base; nothing we need requires iOS 17. Uses `ObservableObject`/`@StateObject`, not
  the iOS 17 `@Observable` macro.
- **Idiomatic SwiftUI throughout.** No UIKit yet. `UIViewRepresentable` reserved for
  isolated cases (e.g. document picker) if needed later.
- **MVVM + shared repository**, mirroring Android:
  `View → ViewModel (ObservableObject) → MediaRepository → PHPhotoLibrary / FileManager`
- **Bundle ID:** `com.anant.MediaCurator` (capital M — intentional, idiomatic on iOS;
  Android side is lowercase `com.anant.mediacurator`. They are separate apps.)

---

## What's been built (file by file)

```
Models/
  MediaType.swift        enum image/video/audio/pdf
  SortMode.swift         enum, rawValues match Android ("DATE_NEWEST", etc.)
  MediaItem.swift        struct; id = PHAsset.localIdentifier (replaces MediaStore id+uri)
  MonthGroup.swift       year/month/items; key "YYYY-MM"
  GalleryItem.swift      enum mirroring Android's sealed class (yearHeader/header/
                         subHeader/media/footer) + structuralVersion
  DuplicateGroup.swift   MD5 group with keepIndex / reclaimableBytes
  MediaStats.swift       per-type visible/hidden counts + bytes

Persistence/
  PreferencesManager.swift   UserDefaults wrapper; keys identical to Android side
  DeletionStatsStore.swift   cumulative deleted count + bytes freed

Repository/
  MediaRepository.swift   PHAsset fetch (image+video), dedupe by name+size,
                          processAndGroupMedia() → (visible, done) month groups
  MediaCache.swift        actor singleton, first-caller-pays, invalidate()
  TrashManager.swift      PHAssetChangeRequest.deleteAssets → Recently Deleted

Utilities/
  Formatters.swift        bytes(), countShort(), monthLabel() — port of GalleryAdapter statics
  DebugLog.swift          os.log wrapper

ViewModels/
  GalleryViewModel.swift  @MainActor; full sort/filter/expand/delete/undo logic,
                          builds GalleryItem tree, PHPhotoLibraryChangeObserver bridge
  HomeViewModel.swift     home hero state computation (curation %, resume month)

Views/
  Home/HomeView.swift             hero card + nav cards + NavigationStack
  Gallery/GalleryView.swift       tree List, sort/filter toolbar, permission gating
  Gallery/MonthHeaderView.swift   YearHeaderRow / MonthHeaderRow / SubHeaderRow
  Gallery/MediaThumbnailView.swift  async PHImageManager thumbnail loading
  Viewer/MediaViewerView.swift    full-screen paging TabView + delete + undo toast
  Viewer/PhotoZoomView.swift      pinch-zoom + double-tap (replaces PhotoView lib)

MediaCuratorApp.swift   @main → HomeView()   (ContentView.swift deleted)
```

Stubbed (show "coming soon"): Duplicates, Hidden, Trash, Settings screens.

---

## Android → iOS API mapping (reference)

| Android | iOS |
|---|---|
| MediaStore (images/video/audio) | Photos.framework (PHAsset, PHFetchResult) |
| MediaStore PDFs + MANAGE_EXTERNAL_STORAGE | **No equivalent** — see PDF gap below |
| PdfBox-Android | PDFKit (built-in) — not yet implemented |
| Glide | PHImageManager.requestImage |
| PhotoView | SwiftUI MagnificationGesture (PhotoZoomView) |
| Gson | Codable |
| OsTrashManager/AppTrashManager | PHAssetChangeRequest (single path; Recently Deleted) |
| ContentObserver | PHPhotoLibraryChangeObserver |
| SharedPreferences | UserDefaults |

Permissions are now in build settings (project uses GENERATE_INFOPLIST_FILE, no
physical Info.plist):
- `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`
- `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`

---

## Known gaps / divergences from Android

1. **PDF discovery.** Android scans the whole filesystem for PDFs via
   MANAGE_EXTERNAL_STORAGE. iOS forbids this. Plan: user-imports PDF folders via
   UIDocumentPickerViewController, OR defer PDFs to a later version. **Decision pending.**
2. **Trash restore.** iOS has no public API to restore from Recently Deleted —
   `TrashManager.restore()` is a no-op stub; user must restore in Photos.app.
   Need to surface a message in the Trash UI.
3. **Audio scope** is narrower on iOS (voice memos via PHAsset; music needs MusicKit).
4. **Duplicates / PDF BM25 search / search engine** — not ported yet.

---

## Environment quirks (MacInCloud managed server)

- **No Accessibility / Screen Recording permission** (managed tier blocks it; the
  dedicated tier upsell was declined). Means: no GUI automation of Xcode. We work
  entirely via filesystem + `xcodebuild` + `simctl`. This is fine — no GUI needed.
- **Simulator-only.** No code-signing identity installed
  (`security find-identity -v -p codesigning` → 0 identities). Real-device / App Store
  builds will need a cert imported later.
- **Apple Dev cert CSR generated** but not yet completed:
  `~/Desktop/MediaCurator_dev.certSigningRequest` (upload to developer.apple.com) and
  `~/Desktop/MediaCurator_dev.key` (private key — keep safe). User to back up the .key.
- **Xcode 26.3**, iOS 26.3 simulators available (iPhone 17 Pro, etc.).
- Project uses **Xcode 16+ synchronized folder groups**
  (`PBXFileSystemSynchronizedRootGroup`) — files added on disk are auto-included in the
  project. **No manual "Add Files to Xcode" step needed.** Do NOT add xcodegen.

---

## ✅ Milestone: first slice verified on simulator (2026-06-25)

The Gallery vertical slice is **running and verified** on the iPhone 17 simulator with
real data. Confirmed working: photo-library permission flow, fetch, year/month grouping,
WhatsApp sub-group split, thumbnails, per-group counts/sizes, and Home curation stats
("90 items · 20.0 MB · 0 reviewed").

### Test data
- `~/Desktop/test-photos/` — 84 images (EXIF dates spread 2021-2024, 14 WhatsApp-named,
  14 screenshots) + 2 sample PDFs. Regenerate via `~/Desktop/make_testdata.py`
  (uses the venv at `~/Desktop/.testdata-venv`, which has `piexif`).
- Load into sim: `xcrun simctl addmedia "iPhone 17" ~/Desktop/test-photos/*.jpg`
- NB: the simulator ships with a few built-in sample photos dated ~2009 — that's why the
  oldest month shows "October 2009". Harmless.

### Simulator gotchas learned (important for next session)
- **Run the GUI** with `open -a Simulator` — `simctl boot` alone is headless (no window).
- **Photos auth in sim:** `simctl privacy grant photos` does NOT make
  `authorizationStatus(.readWrite)` return authorized on iOS 26, and pre-writing TCC.db
  doesn't suppress the prompt either. The app MUST call `requestAuthorization` (now done
  in `HomeViewModel.load()`), and a human taps "Allow Full Access" once in the sim window.
  After that it persists. (We can't tap programmatically — Accessibility is blocked here.)
- The user CAN see/interact with the sim via the MacInCloud remote desktop.
- Capture screenshots headlessly: `xcrun simctl io "iPhone 17" screenshot out.png`.

### Fix made during verification
- `HomeViewModel.load()` now requests photo authorization up front (mirrors Android's
  Home permission gate). Previously only GalleryView requested it, so Home silently
  showed "No media."
- `MediaRepository.mediaItem(from:)` no longer drops an asset when its PHAssetResource
  lookup is empty (fell back to identifier-derived name/size).

## Viewer + delete/undo (built 2026-06-25)

Full-screen pager (`MediaViewerView`) now takes the live `GalleryViewModel` (not a static
array) and pages through `flatMediaItems`. Delete uses a **deferred-delete + undo** flow
owned by the VM:
- `requestDelete` hides items immediately (`pendingDeleteIDs`) and opens a 6 s undo window.
- The actual `PHAssetChangeRequest.deleteAssets` is committed only when the window expires
  (`commitPendingDeletion`). `undoDelete` cancels the commit and unhides.
- **Why deferred:** once committed to iOS "Recently Deleted," no app can restore it
  programmatically — the undo window is the only reversal point. This is a hard platform
  difference from Android (which owned its own trash).
- Undo toast shows in BOTH the viewer and the gallery (survives the viewer dismissing,
  e.g. when the last visible item is deleted).
- Also fixed: `flatMediaItems` now includes ALL visible items regardless of tree
  expansion (was only expanded sub-groups), so the viewer can page the whole library.
- On undo, the viewer jumps back to the restored photo (`returnToID`) — without this it
  showed the neighbor it had advanced to, making undo *look* like a no-op.

**Status: verified working on simulator (delete → undo restores the photo).** Undo window
is 6 s; tested via the user tapping in the sim (we can't tap programmatically).

### Test data backup & repopulation
- Pristine backup: `~/Desktop/test-photos-backup/` and `~/Desktop/test-photos-backup.tgz`.
- Refill the sim after deletions: `~/Desktop/repopulate-gallery.sh` (`--wipe` to reset the
  sim's photo library first). The app only deletes from the sim library, never the backup.

**Open decision (deferred by user):** how the Trash screen should work given iOS can't
restore from Recently Deleted — options are (a) deep-link to Photos' Recently Deleted, or
(b) app-managed hidden album for true in-app restore. Revisit when building Trash.

## Functional spec alignment (source of truth)

`../MediaCurator-android/docs/FUNCTIONAL_SPEC.md` is the **behavioral source of truth** for
the iOS port (per the user). Build every screen to match it. Status vs. spec:

**Built & aligned:**
- HOME hub: hero (tappable card), 2×2 grid (Free up space / Find dupes / Search / Hidden),
  Trash card dimmed when empty, library summary line. (Missing: ⓘ Stats, Help/Settings overflow.)
- GALLERY: Year→Month→(Camera/WhatsApp)→grid tree, 4-col grid, size badges, oldest-first
  default, top sort bar. "Hide Month" footer with the persisted "both sub-groups seen" gate (§3).
- Hide-month Undo toast (§3). VIEWER: paging, zoom, Share, Delete (§4).
- TRASH = spec §8 Option 2 (stage-and-review, app-managed `staged_for_deletion`, commit =
  one batched PHAsset delete). HIDDEN: Year/Month dropdowns + unhide (§5, partial).

**Not yet built (spec sections):**
- §3 Filter chips as a "settings bar" (counts + green✓/red✕, "≥1 filter active" floor, hide
  audio/PDF chips when none). Currently a toolbar filter menu instead.
- §3 Selection mode (long-press multi-select → Share/Move/Delete bar). Sticky header. FABs.
- §3/§4 Toolbar ⓘ Stats, "Restore last deleted (N)".
- §5 HIDDEN: spec wants pick-month = unhide immediately + "keep unhidden?" guard. We use an
  explicit Unhide button instead — revisit to match.
- §6 DUPLICATES, §7 SEARCH, §9 STATS dialog, §10 SETTINGS, §11 HELP — all still stubs.

**§12 decision — RESOLVED (2026-06-25): Option A.** iOS v1 is scoped to the **Photos
library (photos + videos)**. PDFs/audio (which live in the Files app, not PHPhotoLibrary)
and **Search** (§7, primarily PDF-text) are **Phase 2** — a later Files-app integration
(document picker + security-scoped bookmarks + a text index). Consequences in code:
- Home "Search" card removed; `NavDestination.search` dropped.
- Settings "PDF content search" toggle removed.
- Help no longer mentions Search / PDFs.
- Filter chips already hide Audio/PDF when absent, so they simply won't appear in v1.
- Viewer Rename + Open-in-Photos remain omitted (no iOS API).
The PreferencesManager PDF/audio flags and the `.pdf`/`.audio` MediaType cases are kept
(harmless) so Phase 2 can light them up without a model change.

## Curation overhaul — DONE (2026-07-05, matches Android commit 5c35001)

Implemented the full curation-flow rewrite from the updated `docs/FUNCTIONAL_SPEC.md`
(§3, §4, §5, §13) and `docs/CURATION_REGRESSION_TESTS.md`:
- **Pure logic + unit tests** (`Logic/CurationLogic.swift`, `MediaCuratorTests/CurationLogicTests.swift`):
  `WalkLatch` (WL-1…WL-6), `WalkedMonthRule` (revisit), `HideBarDecision` (HB-1…HB-6),
  and reset coverage (§4). All pass.
- **Accordion**: one month open at a time (`openMonthKey`).
- **Pinned Hide-month bar** (replaces footer button): HIDE / SCROLL_TEASER / REVIEW_HINT /
  NONE with amber coach hints; walk-gate fed by header/footer onAppear visibility; revisit
  shortcut + scroll-hint-retired persisted.
- **Open-month-lands-at-top** + **resume** (last-viewed month → Home resume target).
- **Hidden = preview-never-unhides** (§5): grid preview while hidden + explicit "Unhide this month".
- **Reset curation progress** (§4): Settings action, clears only curation keys.
- **First-run animation** (§13): `Views/Onboarding/FirstRunView.swift`, mandatory once/process
  with "Don't show again", replayable from Help.

Walk-gate note: the header/footer visibility is fed via SwiftUI `onAppear/onDisappear`; the
tested `WalkLatch` ordering rule (WL-3b) still holds, but the G-1/G-2/G-3 "settled list"
guards are approximated (no explicit animation-settle gate yet) — revisit if real-device
scrolling shows a false latch. Sticky header (§3) still not built.

## Place search (Android v1.1 §7) — mostly DONE

Ported the offline reverse-geocoding "search & browse by place" feature:
- **Pure core + tests**: `GeoIndex` (3-D unit-sphere k-d tree nearest-city, antimeridian-safe),
  `PlaceBrowse` (ranked aggregation), `PlaceSearch` (diacritic/Turkish normalize + edit-distance-1
  typo tolerance + alias match). All unit-tested (`GeoIndexTests`, `PlaceBrowseTests`, `PlaceSearchTests`).
- **Data**: bundled `geo_cities.tsv` (~15MB) + `country_codes.tsv` in `Resources/`.
- **Store/index**: `PlaceStore` (actor; localIdentifier→city|state|country|aliases, empty=no-GPS),
  `PlaceIndexer` (actor; reads `PHAsset.location` — no extra permission on iOS — → nearest city).
- **UI**: `PlaceBrowseView` (mode A flat cities, mode B drill w/ teal breadcrumb, sort toggle,
  `.searchable` place search → photo grid → viewer). Two gated Home cards + Settings toggle
  (default-on, clears cache off) + GeoNames CC-BY attribution.
- **Verified** end-to-end with GPS-tagged test photos (`~/Desktop/make_gps_photos.py`,
  `~/Desktop/gps-photos/` — London/Paris/Tokyo/NewYork/Bengaluru).

**Remaining for full parity with Android `4202b7c`:**
- Selection actions on place results (long-press multi-select → Share/Delete unified action bar).
- Reinstall-safe place-index backup (Android=Downloads; iOS→iCloud/Documents; deferred).

## Cross-the-board gap audit (2026-07-08) — spec §0–§13

Full section-by-section audit; every implementable gap closed. Remaining items are
**intentional iOS divergences** (platform limits or the Option-A scope decision), not gaps.

**Closed this pass:** viewer video playback (AVPlayer); Hidden tap→viewer + selection actions;
Place browse/search selection actions (shared `SelectablePhotoGrid`); gallery empty states;
sticky scroll header (year always, month when scrolled in); gallery Refresh toolbar; Settings
Share diagnostics; "this app" wording pass. (Earlier: full curation overhaul, place search,
Stats, Duplicates, Settings export/import, Help, first-run demo.)

**Intentional divergences (NOT gaps):**
- General Search (filename + PDF text) and PDF/audio media types — Phase 2 (Option A, §12).
  Place search (photo GPS) IS shipped.
- Viewer **Rename** — no PHAsset filename API on iOS.
- **Show in Photos / Open in gallery** — iOS can't deep-link to a specific asset.
- Selection **Move / Switch Album** — iOS albums are additive; you can't "move out of" the
  library the way MediaStore allows. (Could add "Add to album" later.)
- Cross-reinstall **Downloads backups** (hidden-months, place-index, lifetime "cleaned up",
  "Restore your progress?" offer) — Android-specific; iOS maps to iCloud/Documents; deferred.
  (Durable **demo opt-out** IS done via iCloud KV.)
  - **Decision when implemented (privacy + cost):** put the *small* durable state
    (hidden-months set, curation flags, "cleaned up" counter) in the **iCloud Key-Value store**
    — it survives reinstall, is free, and does **not** count against the user's iCloud quota
    (limits: ~1 MB total, ~1 KB/value, 1024 keys — plenty for these). Do **NOT** back up the
    **place index**: CloudKit-private and iCloud Drive both consume the *user's* iCloud quota
    and would park location-derived data in the cloud (against "nothing leaves the device") —
    it re-scans from EXIF for free, so let it rebuild on reinstall. Also mark any large
    regenerable local file `isExcludedFromBackup = true` so it doesn't bloat the user's iCloud
    device backup (which also counts against their quota).
- **All-files-access rationale** — dropped on iOS (no equivalent).
- Gallery **"Restore last deleted (N)"** toolbar — N/A: iOS can't restore *committed* Photos
  deletions; undo is the post-delete toast + the staged Trash (restore before commit).
- **Jump-swap FAB** (§3) — minor, deliberately omitted (low value).

## Ship to TestFlight (when the $99 Developer Program is enrolled)

Archive-ready: app icon set (`AppIcon.appiconset/icon-1024.png`, generated by
`~/Desktop/make_icon.py`), automatic signing, bundle `com.anant.MediaCurator`, v1.0 (1),
iOS 16 target. Release build for `generic/platform=iOS` compiles clean (arm64, no signing).

Steps once enrolled (Individual, ~$99/yr) on the new Apple ID:
1. Xcode → Settings → Accounts → add the Apple ID; in the target's Signing & Capabilities set
   **Team** to it (automatic signing creates the distribution profile).
2. App Store Connect → register App ID `com.anant.MediaCurator` + create the app record.
3. Xcode → **Product → Archive** (or `xcodebuild archive` + `-exportArchive` with an
   App-Store export options plist). Upload to App Store Connect.
4. Wait ~10–30 min for processing → the build appears under **TestFlight**.
5. Add yourself/friends as testers (email invite or a **public TestFlight link**) → they install
   the TestFlight app → install MediaCurator. No cable; installs OTA anywhere.
- Internal testers = no App Review; external's FIRST build needs a ~1-day Beta App Review.
- TestFlight builds expire after 90 days; push a new build to refresh.
- Before public App Store submission: App Privacy = "No data collected"; run a network-sandbox
  test to back the offline claim; add a launch screen if desired.

## Next steps (in order)

1. Wire up **mark-month-done** round-trip and confirm curation % updates on Home.
2. Then pick the next slice: Duplicates (MD5 hashing) or Settings, and resolve the
   **PDF discovery decision**.
```
