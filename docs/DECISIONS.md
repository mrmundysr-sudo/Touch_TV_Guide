# Decisions

## Approved (owner)
- **Product:** a free TV guide companion — listings, reminders and provider/channel information. It does **not** play TV or video.
- **Data source:** EPGTalk feeds (`US_local_guide.xml.gz`, ~140 local markets, ~72 hours of listings).
- **EPGTalk approval:** the owner (Matthew) reports that **approval to use EPGTalk was obtained from an EPGTalk representative** (contact was made with help from Grok) before any store submission. This **supersedes** the earlier decision (2026-11-05) that the maintainer would not be contacted. The scope of the approval is *use of the public feeds in this app*; the exact written wording is **not in this repository**. Until that correspondence is added (see "Evidence needed before a store release"), the app keeps the conservative posture below, which does not depend on any permission beyond fetching the public feed.
- **Caching / fetching:** the app fetches directly from the EPGTalk public feed and caches **on device only**. No server mirror, CDN or redistribution unless the representative's approval explicitly permits it. The feed URL is configuration (`FeedConfig.DEFAULT_URL`, user-editable in Settings) and the feed is downloaded **at most once every 24 hours** (`FeedPolicy`, enforced in `GuideRepository.refresh`, however the refresh is triggered).
- **Feed window:** about 72 hours. Guide navigation is bounded by the data actually present (`GuideLogic.dataEnd`).
- **Monetization:** **none.** No banner, interstitial or persistent display ads, no rewarded ads, no billing, no subscriptions. Monetization may only be added if Matthew later approves it. (The monetization milestone in the older `BUILD-PLAN.md` is superseded; see that file.)
- **Stacks:** Kotlin + Jetpack Compose (Android); Swift + SwiftUI (iOS).
- **Branches:** `claude/android`, `claude/ios`. No merge to `main`, public release, or store signing without explicit owner approval.
- **No secrets:** none are embedded; there is no account system and no API key.

## Implementation decisions (Android)
- Kotlin 2.0.21, AGP 8.7.3, Gradle 8.14.3 (wrapper checked in), Compose BOM 2024.10.01, Room 2.6.1 (KSP), WorkManager, OkHttp, Coil. `minSdk 26`, `compileSdk/targetSdk 35`. `:core` stays pure JVM.
- Feed tables (channel, program) are replaced on refresh; user tables (numbers, categories, favorites), the Home row and reminders are separate and never touched by a refresh. A failed download/parse leaves everything as it was.
- The raw feed (gz) is kept in the app cache dir so changing market does not re-download.
- **Market selection:** the feed is one file covering all markets; a channel's market is read from the market name at the end of its name (`MarketLogic.marketOfChannel`). Channels naming no market (national digital networks) are shown in every market. Zip → market is "nearest market by distance" (a heuristic, not Nielsen DMA); the user confirms or picks any market.
- **Zip data:** `app/src/main/assets/zips.csv` (zip, lat, lon) is derived from the MIT-licensed `millbj92/US-Zip-Codes-JSON` list (itself US Census-derived centroids); `markets.csv` positions are the mean centroid of the market city's zips. Regenerate with `tools/build_market_data.py`. Attribution is shown in-app (Help → Where the data comes from).
- Providers are labels only (Antenna, Cable/satellite, YouTube TV, Hulu + Live TV, Sling, Fubo, DirecTV Stream, Philo, Other). The app makes **no claim** about which channels a provider carries; numbers are user-editable.
- Changing Home to a *different market* clears numbers, categories, favorites and reminders (channel ids differ per market); re-saving the same market keeps them.
- Reminders use inexact `AlarmManager.setAndAllowWhileIdle` (no exact-alarm permission); `POST_NOTIFICATIONS` is requested with a rationale on Android 13+; denial is handled gracefully; alarms are re-armed on app start and after boot/app update.
- Coarse location (optional) is read once via the last-known location, converted to a suggested zip, and never stored or sent.

## Open risks / evidence needed before a store release
- Add the EPGTalk representative's approval wording (or a link/screenshot of the correspondence) to this repo (e.g. `docs/approvals/epgtalk.md`) and confirm: (1) use in a free app distributed through a store, (2) any attribution EPGTalk wants shown, (3) request-rate expectations (the app uses once/day/device), (4) whether on-device caching and per-device fetching of the raw GitHub-hosted file is covered.
- EPGTalk's feed is community-run: the README says "LEGAL use only", and listings are best-effort. The app states this in Help.
- The raw GitHub URL may rate-limit; `https://epgtalk.com/US_local_guide.xml.gz` is the documented alternative and can be set in Settings.
- Zip → market is approximate; some zips sit in a different DMA than the nearest market.
- Store signing, Play listing, a hosted privacy-policy URL (text in `docs/PRIVACY.md`) and data-safety form are out of scope until the owner approves.
