# EPGTalk permission — what is recorded

## Status: owner-reported, terms NOT yet recorded in this repository

| Item | Value |
|---|---|
| Source | EPGTalk community guides — https://epgtalk.com / https://github.com/acidjesuz/EPGTalk |
| What the owner reports | Matthew reports that approval to use EPGTalk in this app was obtained from an EPGTalk representative (contact was made with help from Grok), before any store submission. (`CLAUDE_FINISH_INSTRUCTIONS.md`) |
| Written terms / correspondence in the repo | **None.** The exact wording, scope and any conditions have not been supplied. |
| Terms flag in the app | `TVGEPGTalkTermsRecorded = false` (Info.plist) |
| Live feed in builds | **On** in all builds (`TVG_LIVE_FEED_ENABLED = YES` in `project.yml`). Owner decision, 2026-11-06: leave it on for the owner's TestFlight testing while the EPGTalk reply to the owner's email is pending |
| Sample data | Still available: Settings › "Use sample data instead", or build with `sample_only` / `sample` |

The app does not claim, anywhere in its UI, that permission has been granted. EPGTalk's README says its guides are provided "for LEGAL use only".

## Before any public release or external testers
The live feed is currently on for internal testing only. Until the terms below are recorded, do not add external testers or submit for review; if EPGTalk declines or restricts use, set `TVG_LIVE_FEED_ENABLED` back to `NO`.

## To record the terms and finish
1. Paste the representative's written wording (or a link/screenshot of the correspondence, with date and sender) into the **Approved terms** section below.
2. Confirm and record: (a) use in a free store-distributed app; (b) any required attribution or notice text; (c) request-rate expectations (the app downloads at most once per day per device, directly from the feed host, cached on device only, never mirrored); (d) which URL to use (`raw.githubusercontent.com` or `epgtalk.com`).
3. Apply configuration: see `docs/FEED_CONFIGURATION.md` — keep `TVG_LIVE_FEED_ENABLED: YES` in `project.yml`, set `TVGEPGTalkTermsRecorded` to `true` in `App/TouchTVGuide/Info.plist`, update `FeedConfiguration` attribution strings if EPGTalk requires different wording.
4. Update the privacy text/App Store privacy answers if the terms change what is disclosed.

## Approved terms
_(empty — to be filled in by the owner)_
