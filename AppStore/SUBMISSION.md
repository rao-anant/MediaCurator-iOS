# App Store submission - step by step

**Good news up front:** the binary (**build 39**) is already uploaded to App Store Connect, and
everything below is done in the **App Store Connect website** (appstoreconnect.apple.com) - from
**any browser on any computer**. None of it needs the Mac. Losing the Mac does **not** block
submitting.

All the assets are in this repo, so you can download them from GitHub on any machine:
- Screenshots: `AppStore/screenshots/iphone/` (4 x 1290x2796) and `AppStore/screenshots/ipad/`
  (6 x 2752x2064)
- All listing text: `AppStore/LISTING.md`

---

## DECISION TO MAKE FIRST - the app's name

The listing text uses **"GalleryCurator"**, but the app itself displays **"MediaCurator"** (it's in
every screenshot, and the Android app on Play is "MediaCurator"). Pick one:

- **Use "MediaCurator" as the App Store name** - matches the screenshots + Android. Cleanest, but
  only if the name is still available on the App Store.
- **Keep "GalleryCurator" as the store name** - Apple allows the store name to differ from the
  on-device name, but the screenshots showing "MediaCurator" may look slightly inconsistent.
  (Optional: change the app's display name to "GalleryCurator" in a later build to match.)

Whichever you choose, use it consistently in the name field below.

---

## Steps in App Store Connect

1. **My Apps -> (the app) -> the "1.0 Prepare for Submission" page.**

2. **App Information** (left sidebar)
   - Name: *your decision above*
   - Subtitle: `Tidy your photo library`
   - Category: Primary **Photo & Video**, Secondary **Utilities** (optional)
   - Content Rights: check "does not contain third-party content" (the app shows only the user's
     own photos + GeoNames place data, which is CC-attributed in-app).

3. **Pricing and Availability** -> Free, all territories (or your choice).

4. **App Privacy** (this is its own section, required before submit)
   - Data collection: **"Data Not Collected."** The app has no network access, no analytics, no
     accounts - nothing leaves the device. Answer every category as not collected.

5. **The 1.0 version page**
   - **Promotional text**, **Description**, **Keywords**, **What's New** - copy verbatim from
     `AppStore/LISTING.md`.
   - **Support URL:** `https://rao-anant.github.io/MediaCurator-iOS/support.html`
   - **Privacy Policy URL:** `https://rao-anant.github.io/MediaCurator-iOS/`
   - **Screenshots:** drag in the files from `AppStore/screenshots/iphone/` (iPhone 6.9" slot) and
     `AppStore/screenshots/ipad/` (iPad 13" slot). Upload in the numbered order (01, 02, ...).
   - **Build:** click "+ Build" (or the Build section) and select **build 39**.
   - **Copyright:** `2026 Anant Rao`
   - **Age Rating:** open the questionnaire, answer everything **None** -> should yield **4+**.

6. **App Review Information**
   - Contact name / phone / email: yours.
   - Sign-in required: **No** (the app has no login).
   - Notes: paste the reviewer note from `AppStore/LISTING.md` ("fully on-device photo-curation
     utility... allow Photos access; the gallery lists photos grouped by month... deletions go to
     Recently Deleted with Undo").

7. **Export compliance** - if asked, "uses non-exempt encryption?" -> **No** (already declared in the
   build via `ITSAppUsesNonExemptEncryption = NO`).

8. **Add for Review -> Submit.** Then it's in Apple's queue (typically ~24-48h).

---

## Checklist before hitting Submit

- [ ] Name decided and entered
- [ ] Subtitle, description, keywords, promo text filled
- [ ] Support + Privacy URLs (both live, verified 200)
- [ ] iPhone 6.9" screenshots uploaded (4)
- [ ] iPad 13" screenshots uploaded (6)
- [ ] Build 39 selected
- [ ] App Privacy = Data Not Collected, completed
- [ ] Age rating questionnaire completed (4+)
- [ ] Review notes added
- [ ] Export compliance answered
