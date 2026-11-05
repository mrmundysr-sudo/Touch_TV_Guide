# Decisions (iOS)

## Approved (owner)
* Free TV guide companion: listings, reminders, provider/channel info. It does **not** play TV or video.
* Data: EPGTalk public feeds, fetched directly, **cached on device only**, no server mirror/redistribution, URL configurable, **refresh at most once a day**; ~72 h coverage, so navigation is bounded by the data.
* **EPGTalk approval:** the owner reports approval was obtained from an EPGTalk representative; the written terms are **not in this repo**. See `docs/EPGTALK_PERMISSION.md`. Until they are recorded, Release builds ship with the live feed **off** (sample data only) and the UI makes no claim of permission.
* No banner/interstitial/persistent display ads, no monetization, no accounts, no tracking, no secrets.
* SwiftUI, iOS 17+, iPhone. No signing/TestFlight/App Store/merge to `main` without explicit owner approval.

## Implementation decisions
* Same data contract and rules as Android (`docs/DATA_MODEL.md`), ported to `Packages/TVGuideCore` with tests.
* **Duplicate channel numbers:** investigated against the real feed. The duplicate `11.1` seen on Android is two different stations the feed carries with the same number (`PIX 11` and `US - ABC News Raleigh-Durham`); neither is a lineup-mapping bug in the numbers themselves. Owner decision: keep the data as the feed provides it. The app flags shared numbers (⚠ in the guide and in Manage channels) and lets the user edit; the "assign number" rule (other channel becomes `?`) is unchanged.
* Unassigned-market channels (national digital networks) are kept in every market, as on Android.
* Zip → market is "nearest market" (heuristic), always user-confirmed. Zip data: MIT-licensed US-Zip-Codes-JSON (Census-derived). Providers are labels only; no claims about carriage.
* Changing market clears customization/reminders; same market keeps them.
* Reminders: local notifications, permission requested only on the first reminder after an explanation; soonest 64 are scheduled (iOS cap); lead time 5/10/15/30 min.
* Location: reduced-accuracy, when-in-use, requested only after an in-app explanation, used once.

## Open items before any store release
* Record EPGTalk's written terms (`docs/EPGTALK_PERMISSION.md`) and then open the feed gate.
* Hosted privacy-policy URL and App Store privacy answers (`docs/PRIVACY.md`).
* Apple signing / TestFlight (out of scope until approved).
* Verify on a physical device: VoiceOver pass, notification delivery timing, location prompt copy.
