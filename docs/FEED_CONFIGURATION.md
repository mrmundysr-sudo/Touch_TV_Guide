# Feed configuration

Everything about the listings provider sits behind one boundary so the feed can be swapped, approved, or disabled without touching the guide UI.

## Where things live
| What | Where |
|---|---|
| Default feed URL, alternate URL, attribution text, User-Agent, size cap | `App/TouchTVGuide/Services/FeedConfiguration.swift` |
| Build gate for the live feed | `project.yml` → `TVG_LIVE_FEED_ENABLED` (currently `YES` for all builds; owner decision for testing) → Info.plist `TVGLiveFeedEnabled` |
| "Terms recorded" flag | Info.plist `TVGEPGTalkTermsRecorded` (must stay `false` until `docs/EPGTALK_PERMISSION.md` has the approved terms) |
| Refresh rule (at most once / 24 h) | `Packages/TVGuideCore/Sources/TVGuideCore/Reminders.swift` → `FeedPolicy` (enforced in `GuideRepository.refresh`) |
| Downloader (network) | `FeedDownloading` protocol; `URLSessionDownloader` in `FeedConfiguration.swift` |
| Parsing (XMLTV) | `XmltvParser.swift` — change this file/type only if the new feed isn't XMLTV |
| Market / lineup mapping | `Markets.swift` (`MarketLogic`), bundled `markets.csv`, `zips.csv` |
| Sample (preview) data | `SampleFeed.swift` |

## Modes
* **Live** — downloads `FeedConfiguration.defaultURL` (user can change it in Settings when the build allows live data), caches the raw file on device (`feed-cache.xml.gz`), filters to the Home market, stores it. At most one download per 24 h; changing the address forces one fresh download.
* **Sample** — generated, clearly labelled ("Sample preview data – not real listings"). Never touches the network. Available in Settings, or as the only mode if the gate is set to `NO`.

## Disabling cleanly
Set `TVG_LIVE_FEED_ENABLED: NO` for every configuration. The app keeps working on sample data; no network request is ever made.

## Swapping to a different approved feed
1. Implement a new parser to `GuideData` (or reuse `XmltvParser` if it is XMLTV).
2. Point `FeedConfiguration.defaultURL` at it and update the attribution strings.
3. If its lineup isn't "all markets in one file", replace `MarketLogic.filterFor` — the repository calls it in exactly one place.
4. Do not scrape Gracenote or any other provider.

## Caching rules (current)
* On device only; no server mirror or redistribution.
* Raw feed kept in Application Support; guide, customization, reminders, Home in separate JSON files — a failed refresh never touches the saved ones.
* Failed or malformed download ⇒ saved guide kept, error shown.
