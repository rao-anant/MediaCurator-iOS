# App Privacy - exact answers

App Store Connect -> your app -> **App Privacy** (left sidebar) -> **Get Started** / **Edit**.

This app has **no network access, no analytics, no accounts, no ads** - nothing ever leaves the
device. On-device-only processing (reading Photos to display them, place indexing, duplicate
hashing) is **not** "data collection" in Apple's sense, which is about data transmitted off-device
or used to track. So the whole section is one answer:

### Question 1 - "Do you or your third-party partners collect data from this app?"
-> **No, we do not collect data from this app.**

That's it. Because you answer **No**, Apple asks **no further data-type questions** - no "what data,"
no "linked to identity," no "tracking." Click through to finish and **Publish**.

### Related fields (elsewhere, not in this questionnaire)
- **Privacy Policy URL** (on the version page): `https://rao-anant.github.io/MediaCurator-iOS/`
- **Privacy Choices URL**: leave blank (not applicable).
- The **Photos permission prompt** the app shows on launch is *not* data collection - it's on-device
  access to display the user's own library. It's covered by the app's usage-description string,
  separate from this section. No action needed here.

### Why "Data Not Collected" is correct (keep for your records / if a reviewer asks)
- No servers, no SDKs, no network calls at all.
- Place names come from a **bundled** GeoNames dataset processed on-device; no location is sent
  anywhere.
- Duplicate detection hashes photos **on-device**; hashes never leave the phone.
- Hidden-months / progress state is stored in local app storage only.
