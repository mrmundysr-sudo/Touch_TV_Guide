# EPGTalk permission — what is recorded

## Status: owner-reported, terms NOT yet recorded in this repository

| Item | Value |
|---|---|
| Source | EPGTalk community guides — https://epgtalk.com / https://github.com/acidjesuz/EPGTalk |
| What the owner reports | Matthew reports that approval to use EPGTalk in this app was obtained from an EPGTalk representative (contact was made with help from Grok), before any store submission. (`CLAUDE_FINISH_INSTRUCTIONS.md`) |
| Written terms / correspondence in the repo | **None.** The exact wording, scope and any conditions have not been supplied. |
| Terms flag in the app | `TVGEPGTalkTermsRecorded = false` (Info.plist) |
| Live feed in Release builds | **Off** (`TVG_LIVE_FEED_ENABLED = NO` in `project.yml`); Release shows labelled sample data only |
| Live feed in Debug builds | On, for development and testing only |

The app does not claim, anywhere in its UI, that permission has been granted. EPGTalk's README says its guides are provided "for LEGAL use only".

## To enable the live feed in a distributed build
1. Paste the representative's written wording (or a link/screenshot of the correspondence, with date and sender) into the **Approved terms** section below.
2. Confirm and record: (a) use in a free store-distributed app; (b) any required attribution or notice text; (c) request-rate expectations (the app downloads at most once per day per device, directly from the feed host, cached on device only, never mirrored); (d) which URL to use (`raw.githubusercontent.com` or `epgtalk.com`).
3. Apply configuration: see `docs/FEED_CONFIGURATION.md` — set `TVG_LIVE_FEED_ENABLED: YES` for Release in `project.yml`, set `TVGEPGTalkTermsRecorded` to `true` in `App/TouchTVGuide/Info.plist`, update `FeedConfiguration` attribution strings if EPGTalk requires different wording.
4. Update the privacy text/App Store privacy answers if the terms change what is disclosed.

## Approved terms
_(empty — to be filled in by the owner)_
