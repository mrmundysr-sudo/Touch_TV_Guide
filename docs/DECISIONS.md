# Decisions

## Approved (owner, 2026-11-05)
- Data source: EPGTalk feeds. The EPGTalk maintainer will **not** be contacted; keep use personal-scale and conservative (see risks).
- Caching: **on-device cache only**. No server-side mirror. One fetch per market, then offline.
- Monetization: none built in for v1. Possible later: watch a rewarded ad to unlock for the day.
- Stacks: Kotlin + Jetpack Compose (Android); Swift + SwiftUI (iOS).
- Build order: shared data layer -> Android -> iOS -> polish.
- Branches: `claude/android`, `claude/ios`. No merge to `main` without approval.

## Open risks
- EPGTalk has no stated license; without contacting the maintainer the app should fetch directly from the public feed, cache on device, and make source and refresh rate easy to change (feed URL is config, refresh at most daily).
- Feed window is ~72h, so the guide is bounded by `GuideLogic.dataEnd`.
