# Claude handoff — finish Touch TV Guide for iOS

You are responsible for completing the iOS app on this branch, `claude/ios`. Work in this branch and commit your work here. Do not merge to `main` or submit for App Review/store release without Matthew's explicit approval.

## Product and source decisions

- This is a free TV guide companion. It provides listings, reminders, and provider/channel information; it must not play TV/video.
- EPGTalk approval: Grok helped Matthew contact an EPGTalk representative, and Matthew reports that approval for use was obtained before any store submission. This supersedes stale statements in `docs/DECISIONS.md`, `docs/BUILD-PLAN.md`, and `docs/PLAN.md` saying the maintainer would not be contacted or approval is pending. Update those docs to accurately record the approval and its actual scope. Do not invent terms: use the written correspondence/owner-provided wording if present; if the exact terms are not in the repo, flag that specific evidence as needed before a store release while continuing implementation.
- Fetch directly from EPGTalk public feeds; cache on device only; no server mirror or redistribution unless the representative's approval explicitly permits it. Keep the URL configurable and refresh no more than once daily.
- Feed coverage is about 72 hours; bound guide navigation by the data available.
- No banner, interstitial, or persistent display ads. Do not add monetization unless Matthew later approves it.
- Preserve the branch's existing architecture and decisions unless code evidence shows a necessary change. Do not introduce secrets or credentials.

## Start by auditing the actual branch

Read `docs/PLAN.md`, `docs/DECISIONS.md`, `docs/DATA_MODEL.md`, and the repository tree. Compare the checklist with the code and CI. This branch currently contains only a plan document and no iOS app implementation, shared contract, parser, storage, UI, or build/CI configuration. Build a working iOS app from the approved product spec and the existing Android core/data contract; do not treat a written plan or mock UI as completion.

## Finish the iOS project end to end

Implement the app, not just a plan or scaffold:

1. Native Swift/SwiftUI app project and reproducible iOS build/CI on macOS; no Apple signing credentials or distribution workflow unless Matthew separately asks.
2. Implement the same data contract and behavior as Android. Port parser/rules with tests (or another clearly documented shared approach); include representative XMLTV fixtures.
3. On-device persistence and refresh; offline use; safe failure behavior that preserves cached listings/customizations.
4. Complete setup: zip/manual location, zip-to-market mapping with source/license attribution, market selection, curated provider/streaming choices, persistence, and initial fetch.
5. Polished, accessible guide grid with channel/time navigation bounded by available data; details; search; categories; favorites; editable channel numbers; themes/font size and clear empty/loading/error states.
6. Local reminders with permission flow and management; honor platform notification limits and reschedule appropriately.
7. Privacy-conscious behavior: no account; explain location use; no data loss on refresh; no false claims about provider lineups.
8. Complete help/guide, metadata, app icons/assets, and functional controls; no placeholder screens, dead controls, mock-only data, or TODOs on core paths.
9. Add CI that builds and tests on macOS. Report commands/results. Keep signing/TestFlight, store submission, and merge to `main` out of scope unless separately approved.

## Completion report

When finished, report the commit SHA, implemented features, build/test commands and results, TestFlight readiness (without starting distribution), known limitations, and any exact EPGTalk approval wording or remaining evidence needed for store release. Continue until the complete usable iOS app and build/test workflow are ready.