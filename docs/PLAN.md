# Touch TV Guide — Feasibility Audit & Scoped Plan

Status: **Historical feasibility audit — superseded by `docs/DECISIONS.md`, `docs/EPGTALK_PERMISSION.md` and the implementation.** The statements below about contacting the maintainer, mirroring, and banner ads are obsolete: the owner reports EPGTalk approval was obtained (terms still to be recorded), there is no mirror, and the app has no ads.
Source: Touch TV Guide Companion App spec v1.0 (locked).

## 1. Audit findings

| Area | Finding | Impact |
|---|---|---|
| EPGTalk data | github.com/acidjesuz/EPGTalk advertises free EPG "for LEGAL use only", ~140 US local markets, updated nightly. | Usable as the spec'd source. |
| Coverage window | The US local feed is ~**72 hours**, not ~7 days. | Right arrow / day picker must be bounded by actual data. |
| Licensing | No license or terms file found; provenance of listings unknown. | **Owner decision**: get written terms from the maintainer before public release. Ads raise the risk. |
| Hosting | The app must not hammer a community host. | Plan a thin cache/mirror so phones fetch one file per market (only if license permits redistribution). |
| Provider lineups | The feed is market-based, not provider-lineup-based. | Provider list = market + curated streaming services; channel numbers default to feed numbers; user customization covers gaps. |
| Zip -> market | Needs a zip->market (DMA) table. | Bundle a static table; verify its source/license. |
| Deep links | Optional per spec. | Android: package intents. iOS: `LSApplicationQueriesSchemes`. Best effort. |
| Reminders | Android 13+ needs POST_NOTIFICATIONS; exact alarms need a permission. iOS caps pending local notifications at 64. | Android: AlarmManager. iOS: schedule the nearest 64, re-schedule on launch/refresh. |
| Privacy | Coarse location used only for zip lookup; no accounts, no secrets in the app. | Short privacy policy needed for store listing. |

## 2. Proposed architecture

Native on both platforms, one shared data contract (`docs/DATA_MODEL.md`, to be written).

- **Android** (`claude/android`): Kotlin, Jetpack Compose, Room, WorkManager, XmlPullParser for XMLTV. Min SDK 26.
- **iOS** (`claude/ios`): Swift, SwiftUI, SwiftData (iOS 17+), BGAppRefreshTask, XMLParser.
- **Offline**: guide renders from the local DB; refresh is additive.
- **User overrides** (number, category, favorite) are stored apart from feed data so refresh never overwrites them. Number conflict -> the other channel becomes `?`; `?` sorts last.
- **Tests**: XMLTV parsing, sort, number-conflict logic, category filter, reminder replacement, Home save/load. CI via GitHub Actions per Touch AutoBuild (iOS needs a macOS runner; no signing material touched).

## 3. Milestones (per platform)

1. Scaffold, CI, data model, XMLTV parser with tests.
2. Setup screen, pre-fill, Home profile, User Guide toggle.
3. Guide grid, time navigation, calendar/home/category icons.
4. Numbers, categories, favorites.
5. Details, reminders, deep links.
6. Search, settings (theme colors, font size), polish, missing-data states.

## 4. Decisions needed from owner

1. EPGTalk licensing: may I contact the maintainer, and is a caching mirror acceptable?
2. Ads: bottom banner ads or fully ad-free?
3. Approve the stacks and milestone order above.
4. Confirm branch names `claude/android` and `claude/ios`.
