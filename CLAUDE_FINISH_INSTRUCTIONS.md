# Claude handoff — finish Touch TV Guide for Android

You are responsible for completing the Android app on this branch, `claude/android`. Work in this branch and commit your work here. Do not merge to `main` or publish/store-release without Matthew's explicit approval.

## Product and source decisions

- This is a free TV guide companion. It provides listings, reminders, and provider/channel information; it must not play TV/video.
- EPGTalk approval: Grok helped Matthew contact an EPGTalk representative, and Matthew reports that approval for use was obtained before any store submission. This supersedes stale statements in `docs/DECISIONS.md`, `docs/BUILD-PLAN.md`, and `docs/PLAN.md` saying the maintainer would not be contacted or approval is pending. Update those docs to accurately record the approval and its actual scope. Do not invent terms: use the written correspondence/owner-provided wording if present; if the exact terms are not in the repo, flag that specific evidence as needed before a store release while continuing implementation.
- Fetch directly from EPGTalk public feeds; cache on device only; no server mirror or redistribution unless the representative's approval explicitly permits it. Keep the URL configurable and refresh no more than once daily.
- Feed coverage is about 72 hours; bound guide navigation by the data available.
- No banner, interstitial, or persistent display ads. Do not add monetization unless Matthew later approves it.
- Preserve the branch's existing architecture and decisions unless code evidence shows a necessary change. Do not introduce secrets or credentials.

## Start by auditing the actual branch

Read `docs/BUILD-PLAN.md`, `docs/PLAN.md`, `docs/DECISIONS.md`, and the repository tree. Compare the checklist with the code and CI. The current branch has a Kotlin JVM `:core` parser/rules and tests, but no Android `:app`, Android UI, persistent storage, or full product flow yet. Treat every milestone as incomplete until its acceptance criteria are implemented and verified.

## Finish the Android project end to end

Implement the app, not just a plan or scaffold:

1. Reproducible Gradle wrapper and Android app module integrated with the existing pure-JVM `:core`.
2. On-device database/repository; feed refresh and resilient XMLTV parsing; offline use; safe refresh failure behavior.
3. Complete first-run setup: zip/manual location, zip-to-market mapping with source/license attribution, market selection, curated provider/streaming choices, persistence, and initial fetch.
4. Polished, accessible guide grid with channel/time navigation bounded by available data; details; search; categories; favorites; editable channel numbers; themes/font size and clear empty/loading/error states.
5. Reminders and notification permission flow; manage/cancel reminders and restore/reschedule as appropriate for Android.
6. Privacy-conscious behavior: no account; explain location use; no data loss on refresh; no false claims about provider lineups.
7. Add/update Android CI so it runs core tests and builds the debug app. Add meaningful tests for parsing, storage/refresh behavior, key product logic, and setup/reminder flows where practical.
8. A complete user-facing help/guide and app metadata/assets. Ensure no placeholder screens, dead controls, mock-only data, or TODOs on core paths.
9. Produce a debug APK artifact for Matthew to install and test. Keep store signing, public release, and merge to `main` out of scope unless separately approved.

## Completion report

When finished, report the commit SHA, implemented features, build/test commands and results, APK artifact location, known limitations, and any exact EPGTalk approval wording or remaining evidence needed for store release. Work milestone by milestone, but continue until the complete usable Android app and installable debug build are ready.