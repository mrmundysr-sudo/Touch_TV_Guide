# Touch TV Guide — Feasibility Audit & Scoped Plan

Status: **PROPOSED — awaiting owner approval before any app code.**
Source spec: Touch TV Guide Companion App spec v1.0 (locked).

## 1. Audit findings

| Area | Finding | Impact |
|---|---|---|
| EPGTalk data | Project (github.com/acidjesuz/EPGTalk) advertises free EPG "for LEGAL use only", ~140 US local markets, updated nightly. | Usable as the spec'd source. |
| Coverage window | EPGTalk US local feed is ~**72 hours**, not ~7 days. | Spec says "typically ~7 days": the right arrow/day picker must be bounded by actual data. UI already specified to limit to available data. |
| Licensing | No license/terms file found; underlying listing provenance unknown. | **Needs owner decision**: ask maintainer for written permission/terms before public release. Ads (spec §10) raise the risk for a commercial use. |
| Hosting | App must not hammer a community host. | Plan a thin cache layer (static mirror/CDN) so phones fetch one cached file per market. Owner decision needed (cost-free option: GitHub Releases/Pages from a scheduled Action, only if license permits redistribution). |
| Provider lineups | EPGTalk is market-based, not provider-lineup-based. Mapping zip -> market -> provider channel numbers is not in the feed. | Provider list = market + curated streaming services; channel numbers default to feed numbers; user customization (spec §4) covers gaps. |
| Zip -> market | Needs a zip->DMA table. | Ship a bundled static table (public-domain-derived) and verify source. |
| Deep links | Opening provider apps is optional (spec §11). | Android: package-name intents. iOS: URL schemes need `LSApplicationQueriesSchemes`. Best effort. |
| Reminders | Android 13+ needs POST_NOTIFICATIONS; exact alarms need SCHEDULE_EXACT_ALARM. iOS caps 64 pending local notifications. | Android: AlarmManager inexact-ok or exact w/ permission. iOS: keep nearest 64, re-schedule on launch/refresh. |
| Privacy | Location is coarse, used only for zip lookup; no accounts, no tracking, no secrets in the app. | Needs a short privacy policy for store listing. |

## 2. Proposed architecture

Native on both platforms (spec preference), sharing one data contract.

- **Shared contract** (`docs/DATA_MODEL.md`, to be written): channel, program, market, user overrides (number, category, favorite), reminder, Home profile.
- **Android** (`claude/android`): Kotlin, Jetpack Compose, Room, WorkManager (background refresh), Hilt, Retrofit/OkHttp + XmlPullParser (XMLTV), Coil. Min SDK 26.
- **iOS** (`claude/ios`): Swift, SwiftUI, SwiftData (iOS 17+), BGAppRefreshTask, UserNotifications, XMLParser. Grid via lazy stacks in a two-axis scroll with a pinned channel column.
- **Offline**: all data and user customization in local DB; guide renders from cache; refresh is additive.
- **User data model**: overrides stored separately from feed data so refresh never clobbers numbers/categories/favorites. Number swap rule: conflict -> other channel becomes `?`.
- **Tests**: unit tests for XMLTV parsing, sort ("?" last), number-conflict logic, category filter, reminder replacement, Home save/load. CI builds on GitHub Actions per Touch AutoBuild (iOS needs a macOS runner; signing material not touched).

## 3. Milestones (per platform)

1. Scaffold + CI + data model + XMLTV parser with tests.
2. Setup screen, pre-fill, Home profile, User Guide toggle.
3. Guide grid, time navigation, calendar/home/category icons.
4. Customization: numbers, categories, favorites.
5. Details, reminders, deep links.
6. Search, settings (theme colors, font size), polish, missing-data states.

## 4. Decisions needed from owner

1. EPGTalk licensing: OK to contact the maintainer, and is a caching mirror acceptable?
2. Ads: keep bottom banner ads or go ad-free (affects licensing risk)?
3. Approve the stacks above and milestone order.
4. Confirm branch names `claude/android` and `claude/ios` (and later PRs to `main`).
