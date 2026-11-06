# Getting Touch TV Guide onto TestFlight

Everything the repo can do is done: the app archives cleanly (CI proves it unsigned on every push), a privacy manifest and encryption/category metadata are in place, and `.github/workflows/testflight.yml` signs, archives and uploads in one manual run. Four things only the account owner can do:

## One-time setup (about 15 minutes)
1. **Create the app record** — App Store Connect → Apps → **+** → New App:
   * Platform **iOS**, Name **Touch TV Guide**, Primary language English
   * Bundle ID **com.touch.tvguide** (appears in the list after step 2's first upload attempt, or register it first at developer.apple.com → Identifiers → **+** → App IDs)
   * SKU **TOUCH-TV-GUIDE-IOS-001** (any unique string)
2. **Create an App Store Connect API key** — App Store Connect → Users and Access → Integrations → App Store Connect API → **+**, access **Admin** (or App Manager). Download the `.p8` (only offered once). Note the **Key ID** and the **Issuer ID** at the top of the page.
3. **Add four repository secrets** — GitHub → Touch_TV_Guide → Settings → Secrets and variables → Actions → New repository secret:
   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | the whole contents of the `.p8` file (or its base64) |
   | `APPLE_TEAM_ID` | your 10-character Team ID (developer.apple.com → Membership details) |
   Never paste these into chat, issues or commits.
4. **Add yourself as an internal tester** — App Store Connect → Users and Access (you are already a user) → then the app → TestFlight → Internal Testing → **+** group → add yourself. Install **TestFlight** from the App Store on your iPhone and sign in with the same Apple ID.

## Each build
GitHub → Actions → **TestFlight upload** → Run workflow on `claude/ios`.
* Leave **live_feed** off for sample data only (the safe default).
* Tick **live_feed** to build with the live EPGTalk feed for *your own* internal testing. This is the owner's explicit choice; the EPGTalk terms are still to be recorded in `docs/EPGTALK_PERMISSION.md` before any public release.
After the run is green, wait ~5–15 minutes for App Store Connect to process the build, then open TestFlight on the iPhone and install it. Internal testers need no Beta App Review.

## What the workflow does
Preflight (fails with a clear message if a secret is missing) → writes the API key → `xcodegen generate` → `xcodebuild archive` with automatic signing through the API key (`-allowProvisioningUpdates`, creates the App ID/profile/cert as needed) → `xcodebuild -exportArchive` with `destination=upload` → build number = the run number.

## If it fails
* *"No profiles / cannot create App ID"* — the API key needs Admin or App Manager access, and the Team ID must match.
* *"Unable to find app record"* — step 1 not done, or Bundle ID/SKU mismatch.
* *Duplicate build number* — re-run (the run number increments).
Logs are attached to the run as `testflight-logs`.
