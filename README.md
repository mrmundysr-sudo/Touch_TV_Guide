# Touch TV Guide — iOS

A free TV guide companion for iPhone: local listings in a cable-style grid, favorites, search, editable channel numbers/categories/order, and show reminders. It does not play TV.

* **Project:** `project.yml` (XcodeGen) → `TouchTVGuide.xcodeproj`, scheme **TouchTVGuide**, SwiftUI, iOS 17+
* **Core:** `Packages/TVGuideCore` (pure Swift package, shared contract with Android)
* **Docs:** `docs/` — ARCHITECTURE, FEED_CONFIGURATION, EPGTALK_PERMISSION, DECISIONS, DATA_MODEL, PRIVACY

## Build and test (macOS, Xcode 16)
```bash
brew install xcodegen
(cd Packages/TVGuideCore && swift test)
xcodegen generate
xcodebuild test -project TouchTVGuide.xcodeproj -scheme TouchTVGuide \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
Open `TouchTVGuide.xcodeproj` in Xcode to run in the simulator. CI: `.github/workflows/ios.yml` (macOS runner, no signing).

## Data source
Listings come from EPGTalk. The owner reports approval, but the written terms are not yet in the repo, so the live feed is **on for the owner's testing** (owner decision, 2026-11-06) while EPGTalk's reply is pending; sample data stays available in Settings. Keep to internal testers until the terms are recorded. See `docs/EPGTALK_PERMISSION.md` and `docs/FEED_CONFIGURATION.md` for exactly what to change once the terms are recorded.

## Permissions
* Location (optional, when-in-use, approximate, used once for a zip suggestion) — explained in-app before the system prompt.
* Notifications — requested when the first reminder is set.

## Known limitations
* Zip → market is "nearest market", not Nielsen DMA; the user can pick any market.
* Provider choice is a label: the data is per market, not per provider lineup.
* Some feed channels share a number (flagged, editable); national digital networks appear in every market (same as Android).
* iOS allows 64 pending notifications; the soonest 64 reminders are scheduled.
* Not yet verified on a physical device (CI runs on the simulator); no signing, TestFlight or App Store work done.
