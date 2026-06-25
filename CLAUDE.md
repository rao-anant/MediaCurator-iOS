# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **▶ Resuming the iOS port?** Read [`PORTING_NOTES.md`](./PORTING_NOTES.md) first — it
> is the living handoff doc: current build status, design decisions, file-by-file
> inventory, environment quirks, and the exact next steps.

## Repository layout

The iOS port is **underway** (no longer an empty placeholder). The first vertical slice
(Gallery end-to-end) is written and builds for the iOS Simulator — see `PORTING_NOTES.md`.
The original Android implementation remains the reference at `../MediaCurator-android/`.

```
~/dev/mediacurator/
├── MediaCurator-iOS/          ← this repo (placeholder)
└── MediaCurator-android/      ← live Android app
```

---

## Android project — build commands

All commands run from `MediaCurator-android/`.

```bash
# Debug APK (installs to connected device)
./gradlew assembleDebug
./gradlew installDebug

# Release APK — requires keystore.properties (gitignored)
./gradlew assembleRelease

# Release AAB for Play Store upload
./gradlew bundleRelease

# Clean
./gradlew clean
```

**Signing**: create `keystore.properties` at the repo root before a release build:
```
storeFile=mediacurator.keystore
storePassword=...
keyAlias=mediacurator
keyPassword=...
```

The keystore file and `keystore.properties` are gitignored and must be kept as an external backup — losing the keystore blocks future Play Store updates.

There are no unit or instrumented tests in the project.

---

## Android architecture

**Stack**: Kotlin · MVVM (AndroidViewModel + LiveData) · ViewBinding · SharedPreferences (no database) · No network access

**Key classes and their roles**:

| Class | Role |
|---|---|
| `MediaRepository` | All MediaStore I/O: fetches images/videos/audio/PDFs, resolves "best date" per type, MD5 hashing, PDF text extraction via PdfBox |
| `MediaCache` | Process-wide singleton; first caller (usually Home) pays for the MediaStore scan; others reuse it; invalidated after mutations |
| `PreferencesManager` | Wraps SharedPreferences — hidden months, sort mode, expanded tree state, last-deleted batch, feature flags |
| `Models.kt` | All data types: `MediaItem`, `MonthGroup`, `GalleryItem` (sealed), `DuplicateGroup`, `SortMode`, `MediaStats` |
| `TrashManager` | Interface with two impls: `OsTrashManager` (API 30+ — flips `IS_TRASHED`) and `AppTrashManager` (API ≤29 — moves to hidden folder). Singleton via `TrashManager.get(context)` |
| `GalleryViewModel` | Owns the gallery item list, sort/filter state, deletion, undo, and the ContentObserver that auto-refreshes on external changes |
| `PdfBm25Index` / `PdfIndexStore` | BM25 full-text search over PDF content; index built once in background, persisted to app files |
| `PhotoHashStore` / `DuplicatesViewModel` | MD5-based exact duplicate detection; hashes computed incrementally in background and cached |
| `SearchEngine` | Fuzzy filename search + BM25 PDF content search, merged and ranked |

**Activity navigation**:
```
HomeActivity (launcher)
├── MainActivity          → MediaViewerActivity (full-screen swipe viewer)
│                          └── PhotoViewerActivity (pinch-zoom photos)
├── DuplicatesActivity    (side-by-side duplicate review)
├── SearchActivity        (filename + PDF content search)
├── HiddenActivity        (manage hidden/done months)
├── TrashActivity         (soft-deleted items, 30-day retention)
├── SettingsActivity
└── HelpActivity
```

**"Done months" / hiding**: `PreferencesManager.getDoneMonths()` stores a `Set<String>` of `"YYYY-MM"` keys. `MediaRepository.processAndGroupMedia()` splits items into visible vs. done `MonthGroup` lists based on this set. Done months are never deleted from device storage.

**Date resolution**: Each media type has its own resolver in `MediaRepository` because MediaStore timestamps are unreliable in different ways for each type (EXIF for images, filesystem mtime for audio, DATE_ADDED for PDFs). All resolvers fall back to extracting YYYY-MM-DD from the filename before trusting metadata.

**`GalleryItem` sealed class**: The RecyclerView list is flat but logically tree-shaped — `YearHeader`, `Header` (month), `SubHeader` (WhatsApp sub-group), `Media` (individual file), and `Footer`. `GalleryAdapter` maps view types to these. The `structuralVersion` field signals the adapter to call `notifyDataSetChanged()` (bypassing DiffUtil) for large structural changes like re-sorting.

**WhatsApp sub-grouping**: Within each month, items whose `RELATIVE_PATH` contains `"whatsapp"` (case-insensitive) are split into a separate `SubHeader` group ("WhatsApp") alongside the main "Camera & Others" group.

---

## Dependencies of note

- `com.github.bumptech.glide:glide:4.16.0` — thumbnail loading
- `com.github.chrisbanes:PhotoView:2.3.0` — pinch-zoom in the viewer
- `com.tom-roush:pdfbox-android:2.0.27.0` — PDF text extraction (requires `PDFBoxResourceLoader.init()` once per process, called in `MediaRepository.init`)
- `com.google.code.gson:gson:2.10.1` — JSON for backup/restore of hidden-months list

---

## Play Store notes

See `PLAYSTORE.md` for store listing copy, `MANAGE_EXTERNAL_STORAGE` justification text, data safety answers, and release checklist. App ID: `com.anant.mediacurator`.
