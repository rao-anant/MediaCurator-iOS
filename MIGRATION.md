# Moving the build/release setup to a new Mac

This is the **sanitized** migration guide (safe to keep in git). The actual **secrets** are NOT
here and never should be — they live in an offline backup folder (`mac-migration-backup/`) that
must be copied off the old Mac by hand. This file is the recovery *procedure* + the non-secret
identifiers, so the steps survive even if the USB copy is lost.

## What the offline backup must contain (get these off the old Mac before losing it)

- `AppleDistribution_MediaCurator.p12` — distribution certificate **+ private key**. The private
  key exists nowhere else; without it the cert must be revoked + regenerated.
- `AuthKey_<KEYID>.p8` — App Store Connect API key. **Apple allows downloading a .p8 only once**;
  if lost, create a new API key in App Store Connect → Users and Access → Integrations → Keys.
- `id_ed25519` (+ `.pub`) — GitHub SSH key. (Replaceable: make a new key, add the .pub to GitHub.)
- `GalleryCurator AppStore.mobileprovision` — App Store provisioning profile (regenerable).
- `MediaCurator_dev.certSigningRequest` — CSR that created the cert (only for a from-scratch redo).
- Claude memory `*.md` files → drop into the new machine's
  `~/.claude/projects/<url-encoded-project-path>/memory/`.
- The `.p12` password, the build-keychain password, and the ASC API **Key ID / Issuer ID** — these
  are written in the backup folder's own README, not committed here.

## Non-secret identifiers

| Thing | Value |
|---|---|
| Apple Team ID | `4AK585R8JQ` |
| Bundle ID | `com.anant.MediaCurator` |
| App Store Connect app ID | `6789437059` |
| TestFlight Internal Testers group ID | `c70afe88-3ff0-43e0-ae20-dd27e6d1358e` |
| Provisioning profile name | `GalleryCurator AppStore` |
| git identity | Anant Rao / anant.rao@gmail.com |
| Repos | `git@github.com:rao-anant/MediaCurator-iOS.git`, `…/MediaCurator-android.git` |

## New-Mac setup (summary)

1. Install Xcode; sign in to the Apple ID under Xcode → Settings → Accounts.
2. SSH: copy `id_ed25519`(+`.pub`) to `~/.ssh/`, `chmod 600` the private key, `ssh -T git@github.com`
   to confirm, then clone both repos and set `git config --global user.name/email`.
3. Import `AppleDistribution_MediaCurator.p12` (double-click, enter its password) and double-click
   the `.mobileprovision` to install it.
4. Put the `.p8` where the assign script expects it (or edit the script's path).
5. `python3 -m venv venv && venv/bin/pip install pyjwt cryptography requests`.
6. Build + upload with the manual-signing recipe (see the memory note
   `testflight-cli-signing.md`): `xcodebuild … archive` (team `4AK585R8JQ`, identity
   "Apple Distribution", profile "GalleryCurator AppStore") → `xcodebuild -exportArchive` with
   `exportOptions.plist` → run the assign script (bump the build number) to hand the build to
   Internal Testers.

## Not covered here

- **Android release keystore** (`mediacurator.keystore` + `keystore.properties`) is on the Android
  build machine, not the iOS Mac. Back it up from there — losing it blocks all future Play Store
  updates (Play app id `com.anant.mediacurator`).
- **App Store screenshots** — still to be captured on-device before submission.
