# Touch TV Guide — Android-first build plan

Branch: `claude/android`  
Status: **Milestones 1–6 implemented on this branch; Milestone 7 (monetization) is CANCELLED by owner handoff; Milestone 8 partly done (debug APK, CI) — store signing/release awaits owner approval.**  
Authority: follow `docs/DECISIONS.md` (updated with the owner handoff in `CLAUDE_FINISH_INSTRUCTIONS.md`). **The owner handoff supersedes this file where they disagree:** the app has **no monetization of any kind** (no rewarded ads, billing or subscription) unless Matthew later approves it, and **EPGTalk approval has been obtained** (see DECISIONS), so the “maintainer will not be contacted” text below is stale. `docs/PLAN.md` remains the feasibility audit; where PLAN and this file disagree on product rules, **this build plan + DECISIONS (as amended here) win**.

Goal: ship a usable Android app on top of the existing JVM `:core` module, then port to iOS. This document is the Android track only. Do **not** merge to `main` without owner approval.

---

## Pre-build / open questions (confirm before app code)

Do these before writing `:app` code. They are not blockers for scaffolding, but they are blockers for a public or store release.

| Item | Current decision | What to confirm / do |
|---|---|---|
| **EPGTalk licensing** | ~~Maintainer will not be contacted~~ **Superseded:** the owner reports EPGTalk approval was obtained; exact wording still needs to be filed in the repo before a store release (`docs/DECISIONS.md`). Keep fetching conservative regardless. | Treat as open risk for any non-personal release. Fetch only from the public feed URL (config), cache **on device**, refresh at most daily. Make the feed URL easy to swap. Do not redistribute EPGTalk data from our own host/CDN. |
| Caching | **On-device cache only.** No server-side mirror. | Stick to Room (+ optional raw XML file on disk). No GitHub Releases/Pages mirror. |
| **Monetization (authoritative)** | See below. **Banner ads are explicitly REJECTED** — do not add banner/interstitial inventory or bottom-banner UI in any milestone. | Implement only: (1) rewarded day-pass, (2) one-time unlock, (3) Touch-family subscription. Record product IDs and Play Billing / AdMob (rewarded-only) setup before Milestone 7. Sync `docs/DECISIONS.md` when convenient. |
| Feed window | EPGTalk US local ≈ **72 hours**, ~140 markets. | Bound right-arrow / day picker with `GuideLogic.dataEnd`. Do not hard-code 7 days. |
| Zip → market | Still needed (PLAN audit). | Bundle a static zip→DMA/market table (public-domain-derived). Verify source attribution before store. |
| Provider lineups | EPGTalk is market-based, not provider-lineup-based. | Setup: market + curated streaming providers; channel numbers from feed; user customization covers gaps. |
| Privacy / store | Coarse location only for zip; no accounts. | Short privacy policy required before Play listing (Milestone 8). Disclose rewarded ads + Play Billing in data-safety / policy text. |

### Monetization model (do not reintroduce banners)

**Banner ads (and other persistent display ads) are explicitly rejected for this app.** Future work must not add banner units, sticky bottom ads, or “banner for revenue” variants. PLAN.md historical notes about bottom banner ads are obsolete for this product.

Allowed paths only:

1. **Rewarded ads (day pass):** User watches **four** ~**30-second** rewarded ads → unlock the **complete** app for **one day** (local calendar day or rolling 24h — pick one in M7 and document it; default recommendation: rolling 24h from fourth completion).
2. **One-time purchase:** Buy the app outright (non-consumable Play product) → permanent unlock on that Google account / license.
3. **Subscription:** A subscription that covers **all Touch family apps** (shared entitlement). This app must recognize the family sub as fully unlocked; product/SKU naming and cross-app verification are part of Milestone 7.

Locked / free tier behavior (define precisely in M7): until unlocked, allow setup + limited preview as needed for conversion; do not show banners while locked.

**Already done (do not redo):**

- Shared Kotlin `:core` — `Models.kt`, `GuideLogic.kt`, `XmltvParser.kt`
- Unit tests — `core/src/test/kotlin/.../CoreTest.kt`
- Docs — `docs/DATA_MODEL.md`, `docs/DECISIONS.md`, `docs/PLAN.md`
- CI — `.github/workflows/android.yml` runs `gradle :core:test` on `claude/android`
- Root Gradle — `settings.gradle.kts` includes `:core` and notes `:app` as next; `build.gradle.kts` applies Kotlin JVM 2.0.21; `core/build.gradle.kts` is JVM 17

**Not in tree yet:** Gradle wrapper, `:app`, Android plugin, Compose, Room, networking, any UI, billing, or ad SDKs.

---

## Milestone 1 — Gradle wrapper + Android `:app` wired to `:core`

**Why first:** `settings.gradle.kts` already says `:app` is the next milestone. CI today installs Gradle via `gradle/actions/setup-gradle` (`8.14.3`); a checked-in wrapper makes local + CI builds reproducible and unlocks the Android plugin.

### Tasks

1. Add Gradle Wrapper (`gradlew`, `gradlew.bat`, `gradle/wrapper/*`) pinned to **8.14.3** (match CI).
2. Convert the root build to an Android multi-module layout:
   - Root `build.gradle.kts`: declare Android Gradle Plugin + Kotlin Android/Compose plugins (`apply false`). Keep Kotlin **2.0.21** unless AGP forces a bump — document any bump in DECISIONS.
   - `settings.gradle.kts`: `include(":core", ":app")`; add `pluginManagement` / `dependencyResolutionManagement` (Google + Maven Central) as needed for AGP.
3. Create `:app` module:
   - `app/build.gradle.kts` — `com.android.application`, Kotlin, Compose, `minSdk 26` (per PLAN), `targetSdk`/`compileSdk` current stable.
   - `applicationId` e.g. `com.touch.tvguide`
   - `implementation(project(":core"))`
   - Minimal `MainActivity` + empty Compose theme so the APK launches.
4. Keep `:core` as **pure JVM** (no Android dependency) so iOS can still share the contract via the same rules/tests. Do not turn `:core` into an Android library unless forced.
5. Update `.github/workflows/android.yml`:
   - Prefer `./gradlew :core:test` (wrapper).
   - Add a job (or step) `./gradlew :app:assembleDebug` once `:app` exists (needs Android SDK on the runner — use `android-actions/setup-android` or `gradle/actions` + SDK licenses).
6. Extend `.gitignore` if needed (`*.apk`, `.cxx/`, captures, etc.) without ignoring the wrapper jar.

### Reuse

- `settings.gradle.kts`, root + `core/build.gradle.kts`
- `.github/workflows/android.yml`
- Package namespace already used in core: `com.touch.tvguide`

### Acceptance criteria

- [ ] `./gradlew :core:test` passes locally and in CI.
- [ ] `./gradlew :app:assembleDebug` produces a debug APK.
- [ ] Installing/running the APK shows a blank/scaffold Compose screen (no crash).
- [ ] `:core` still has **zero** Android dependencies.
- [ ] No merge to `main`.

---

## Milestone 2 — Room database for channels / programs

**Why next:** Offline-first is decided (on-device only). UI and fetch both need a durable store. Keep **feed data** and **user customization** in separate tables/entities so refresh never clobbers user overrides (`docs/DATA_MODEL.md`).

### Tasks

1. Add Room (+ KSP) to `:app` only.
2. Entities mapped from core types (store primitives; map to/from `Channel`, `Program`, `Customization`, `HomeProfile`):
   - Feed: channels, programs (program PK = `channelId|startMillis` per `Program.key()`).
   - User: customization maps (numbers, categories), favorite channel/program sets, single `HomeProfile` row.
   - Metadata: last-fetch timestamp, feed URL / market id used.
   - Leave room (schema) for unlock state used later in Milestone 7 (day-pass expiry, owned license flags) — or add those tables in M7; either is fine if documented.
3. DAOs: replace-all for a market refresh; query programs by channel + time window; load/save customization and home.
4. Repository layer in `:app` that:
   - Reads Room → builds `GuideData` + `Customization`
   - Exposes suspend/Flow APIs for the UI
   - Calls **only** `GuideLogic` for sorting, numbers, categories, favorites, windows, search — do not reimplement rules in the app.
5. Instrumented or JVM Room tests for insert/replace/query and “refresh does not wipe customization”.

### Reuse

- `core/.../Models.kt` — `Channel`, `Program`, `GuideData`, `Customization`, `HomeProfile`, `Program.key()`, `UNKNOWN_NUMBER`
- `core/.../GuideLogic.kt` — all pure rules
- `docs/DATA_MODEL.md` — contract the Room schema must honor

### Acceptance criteria

- [ ] Can insert a fixture `GuideData` and read it back as the same channels/programs.
- [ ] Saving customization, then replacing feed rows, leaves customization intact.
- [ ] `GuideLogic.sorted` / `window` / `dataEnd` work on repository-loaded data (unit or instrumented test).
- [ ] Empty DB is a clean “no data” state for later UI (no crash).

---

## Milestone 3 — Feed fetch (XMLTV download + existing parser)

**Why next:** Populate Room from the real (or fixture) XMLTV source before investing in grid polish.

### Tasks

1. Networking in `:app` (OkHttp is enough; Retrofit optional): GET the configured feed URL, stream body to `XmltvParser.parse(InputStream)`.
2. Config object: feed base URL, market id, refresh policy (**at most daily**). Hard-code a known-good EPGTalk market URL for debug; keep it swappable.
3. After parse: write `GuideData` into Room (replace feed tables for that market); set last-fetch time.
4. WorkManager periodic + one-shot refresh (PLAN stack). Respect conservative rate: skip if last fetch < 24h unless user pulls to refresh.
5. Error handling: network failure → keep cache; parse partial/tolerant behavior already in `XmltvParser` (bad programmes skipped).
6. Optional: cache raw XML file on disk for debugging; Room remains source of truth for UI.
7. Unit test: parse a checked-in sample XMLTV snippet (or reuse CoreTest fixtures) through the repository path into Room (can be Robolectric/instrumented).

### Reuse

- `core/.../XmltvParser.kt` — `XmltvParser.parse(input)`
- `CoreTest.kt` — parser/time fixtures and expectations
- DECISIONS: on-device only, no mirror, feed URL as config, ≤ daily refresh

### Acceptance criteria

- [ ] Debug build can fetch (or load fixture), parse via `XmltvParser`, and persist to Room.
- [ ] Second launch with airplane mode still shows cached guide data.
- [ ] Failed fetch does not clear existing Room feed data or customization.
- [ ] Feed URL and refresh interval are centralized config, not scattered string literals.

---

## Milestone 4 — Compose guide grid UI

**Why next:** First visible product surface. Until Milestone 5, use a debug default market / last-fetched data (or “open guide” with empty-state CTA). Until Milestone 7, debug builds may treat the app as unlocked for development.

### Tasks

1. Guide screen: two-axis scroll grid — pinned channel column (number + name) + time-based program cells.
2. Time window from “now” (or selected origin); horizontal pan/arrows; **clamp** with `GuideLogic.dataEnd(programs)` (~72h of data, not 7 days).
3. Per-channel row content via `GuideLogic.window(...)`; empty → show **“No listings”**.
4. Channel order via `GuideLogic.sorted`; show `GuideLogic.effectiveNumber`.
5. Category filter chip/row using `GuideLogic.byCategory`; favorites strip using `GuideLogic.favorites`.
6. Program tap → details sheet (title, time, description).
7. Basic customization hooks on this screen (can be minimal UI):
   - Long-press / edit number → `GuideLogic.assignNumber` then persist customization.
   - Toggle favorite channel/program → `GuideLogic.toggleFavorite*`.
8. Coil for `logoUrl` when present.
9. Loading / empty / error states wired to repository + fetch.
10. (Stretch in this milestone or early M6) Search using `GuideLogic.search`.
11. **Do not** reserve layout space for banners or add any display-ad placeholders.

### Reuse

- `GuideLogic` for every rule listed in `docs/DATA_MODEL.md`
- Room repository from M2–M3
- PLAN UI notes: right-arrow limited by available data; “No listings” for empty windows

### Acceptance criteria

- [ ] With cached data, grid shows channels in numeric order (`?` last).
- [ ] Scrolling time forward stops at `dataEnd`; no blank infinite future.
- [ ] Category filter and favorites match GuideLogic behavior covered by `CoreTest`.
- [ ] Assigning a duplicate number forces the other channel to `?` and persists after process death.
- [ ] Works offline from Room.
- [ ] No banner / display-ad UI in the layout.

---

## Milestone 5 — Setup / onboarding flow

**Why after grid:** Grid can be developed against fixtures; setup is what selects market/provider and seeds `HomeProfile` for real users.

### Tasks

1. First-run flow when no `HomeProfile` exists:
   - Zip (optional coarse location → zip; permission rationale; deny = manual entry).
   - Map zip → market via bundled static table.
   - Pick provider (market broadcast + curated streaming list — not a full lineup DB).
2. Save via `GuideLogic.saveHome` → Room; trigger initial feed fetch for that market.
3. Home icon: load profile (`GuideLogic.loadHome`); long-press reset → `GuideLogic.resetCustomization` (clears numbers/categories, **keeps favorites**) with confirmation.
4. Overwrite existing Home only after confirmation (DATA_MODEL / GuideLogic comment).
5. Entry to User Guide / help toggle if still in the locked spec (keep thin: link or local markdown screen).
6. After setup, land on the guide grid.

### Reuse

- `HomeProfile`, `Customization`, `GuideLogic.saveHome` / `loadHome` / `resetCustomization`
- DECISIONS provider/market approach from PLAN audit
- Fetch pipeline from M3

### Acceptance criteria

- [ ] Fresh install → setup → fetch → grid with that market’s channels.
- [ ] Relaunch skips setup and restores Home + customization.
- [ ] Changing Home with confirmation replaces profile and refetches; cancel leaves data alone.
- [ ] Reset clears numbers/categories only; favorites remain.
- [ ] Location permission denied still allows full manual zip setup.

---

## Milestone 6 — Reminders

### Tasks

1. Reminder model in Room (program key, channelId, startMillis, title, enabled).
2. Schedule with `AlarmManager` (inexact OK for v1; exact only if you take `SCHEDULE_EXACT_ALARM` and document it).
3. Android 13+: request `POST_NOTIFICATIONS` before first reminder; graceful deny.
4. Notification tap opens program details / guide at that time.
5. On feed refresh: drop or update reminders whose programs disappeared; reschedule pending set on boot (`BOOT_COMPLETED`) and on app start.
6. UI: “Remind me” from program details; list/manage in settings or details.
7. Tests: reminder replace/cancel logic (pure where possible).

### Reuse

- `Program.key()`, program start/stop from core models
- PLAN audit notes on POST_NOTIFICATIONS / exact alarms

### Acceptance criteria

- [ ] User can set a reminder for a future program and receives a notification near start (emulator/device).
- [ ] Cancel removes the scheduled alarm and Room row.
- [ ] App reboot reschedules still-valid reminders.
- [ ] No crash if notification permission denied; user is told reminders need it.

---

## Milestone 7 — ~~Monetization~~ CANCELLED (superseded by owner handoff)

> **Not implemented, by decision.** `CLAUDE_FINISH_INSTRUCTIONS.md`: *no banner, interstitial or persistent display ads; do not add monetization unless Matthew later approves it.* The app has no ad SDK, billing library, entitlement model or paywall. The text below is kept only as history of the earlier proposal.

**Why here:** Core product (guide, setup, reminders) should work first; then gate “complete app” behind the three approved unlock paths. **Banner ads remain forbidden** in this milestone and afterward.

### Tasks

1. **Entitlement model** (Room + in-memory):
   - States: `locked` | `dayPass(expiresAt)` | `owned` (one-time) | `familySub(active)`.
   - Single `isUnlocked()` used by UI/navigation; purchase and sub beat day-pass.
   - Persist day-pass expiry locally; re-validate Play entitlements on launch and on BillingClient reconnect.
2. **Rewarded ads — four × ~30s → one day unlock:**
   - Integrate a **rewarded-only** ad SDK path (e.g. Google Mobile Ads rewarded units). **Do not** register banner, native, or interstitial units.
   - Paywall / unlock screen: progress “0/4 … 4/4”; each completed rewarded callback increments; cancel/fail does not count.
   - On 4/4: set day-pass expiry (document rolling 24h vs calendar day; prefer rolling 24h).
   - After expiry, return to locked; ads can be watched again the same way.
   - Debug/test ads for automated and manual QA.
3. **One-time purchase (buy the app):**
   - Play Billing Library: non-consumable product (SKU TBD, e.g. `touch_tv_guide_unlock`).
   - Purchase flow, acknowledge, grant `owned`; restore purchases on new device / reinstall.
4. **Touch family subscription:**
   - Subscription product (SKU TBD) that unlocks **all Touch family apps**.
   - This app queries Play for that sub (and/or a shared license signal documented for the family) and treats an active sub as full unlock.
   - Handle grace period / account hold per Play policies; when sub lapses, fall back to owned → day-pass → locked.
   - Document how other Touch apps will share the same product IDs / verification approach (even if those apps are not built yet).
5. **Paywall UI:** Clear choices — Watch 4 ads (day), Buy once, Subscribe (Touch family). No banner creatives anywhere on this screen.
6. **Gate:** Wire `isUnlocked()` so complete features require unlock; keep enough preview that setup/feed still demonstrate value. Debug build flag to force unlocked for engineering.
7. Privacy / Play: disclose ads (rewarded) and in-app purchases; no under-13 targeting assumptions without owner sign-off.
8. Tests: entitlement priority (sub > owned > day-pass > locked); day-pass expiry; purchase restore; “banner unit must not exist” checklist in PR template or code review notes.

### Reuse

- App navigation/settings from M4–M6
- Room from M2 for persisting day-pass expiry / cached entitlement flags
- This section’s monetization rules (not PLAN.md banner notes; not DECISIONS “none in v1”)

### Acceptance criteria

- [ ] Completing **four** rewarded ads unlocks the complete app until day-pass expiry; partial watches do not unlock.
- [ ] One-time purchase unlocks permanently (for that license) and restores after reinstall.
- [ ] Active Touch-family subscription unlocks this app without extra purchase; lapse removes sub entitlement only.
- [ ] Entitlement priority: family sub / one-time ownership outrank day-pass; no double-charge confusion in UI copy.
- [ ] **Zero banner (or other persistent display) ad units** in code, layouts, or AdMob console config for this app.
- [ ] Locked users never see banner placeholders; only the rewarded/paywall flows above.
- [ ] Debug unlock flag works for CI/manual testing without real charges.

---

## Milestone 8 — Store packaging

Only after M1–M7 are solid enough for a personal or closed test track. Respect EPGTalk **personal-scale** posture until licensing is clearer. Monetization (M7) should be testable on an internal track before wide release.

### Tasks

1. Application id, versionCode/versionName, release signing config (secrets via CI or local; never commit keystore).
2. ProGuard/R8 keep rules for Room / Kotlin / Billing / rewarded ads SDK if minify enabled.
3. Adaptive icon, label “Touch TV Guide”, theme colors/font-size settings if still required by spec (can be minimal).
4. Privacy policy URL (zip/location use, on-device cache, no accounts, data source disclosure, **rewarded ads**, **Play Billing** / subscription).
5. Play Console listing: short/full description, screenshots, content rating, data safety form; declare IAP + ads (rewarded only).
6. Create Play products: one-time unlock + Touch-family subscription; link rewarded ad unit IDs for release.
7. CI: `assembleRelease` (unsigned or with secrets); optional Play upload later.
8. Deep links to provider apps (optional, PLAN §11): package intents; best-effort.
9. Final pass: missing-data states, theme, font size, search polish from PLAN milestone 6.
10. Confirm release binary has **no banner ad dependency or layout**.

### Reuse

- Entire `:app` + `:core` stack + Milestone 7 entitlements
- Branch policy: no merge to `main` without approval

### Acceptance criteria

- [ ] Signed release (or Play internal testing) APK/AAB installs and completes setup → guide → reminder on a physical device.
- [ ] Privacy policy and data-safety answers match actual behavior (on-device cache, rewarded ads, IAP/sub).
- [ ] Internal testers can exercise rewarded 4-ad day-pass, one-time buy, and subscription unlock.
- [ ] No banner/display ad SDK usage in the release configuration.
- [ ] Owner explicitly approves any PR to `main` and any public listing.

---

## Suggested working order (checklist)

```
Pre-build notes acknowledged (EPGTalk conservative use; banners rejected; monetization model locked)
→ M1 Wrapper + :app scaffold + CI assembleDebug
→ M2 Room + repository + GuideLogic wiring
→ M3 Fetch + XmltvParser + WorkManager
→ M4 Compose guide grid (+ light customization; no banner chrome)
→ M5 Setup / Home profile
→ M6 Reminders
→ M7 Monetization (rewarded 4×30s day-pass, one-time buy, Touch-family sub)
→ M8 Store packaging / policy / Play products
→ (Later) iOS port from docs/DATA_MODEL.md + CoreTest cases on claude/ios
→ (Docs follow-up) Align docs/DECISIONS.md monetization with this plan
```

## Out of scope for this Android-first plan

- iOS implementation (separate track on `claude/ios` after Android is usable)
- Server-side EPG mirror / CDN
- **Banner ads, interstitial ads, or any persistent display ads** (explicitly rejected)
- Contacting the EPGTalk maintainer
- Merging to `main` without owner approval

## Mapping to older PLAN.md milestones

| This build plan | Rough PLAN.md §3 equivalent |
|---|---|
| Done already | PLAN M1 (scaffold + CI + model + parser) for Android core |
| M1–M3 here | Finish Android scaffold + storage + feed |
| M5 | PLAN M2 (setup / Home) |
| M4 | PLAN M3–M4 (grid + customization) |
| M6 | PLAN M5 (reminders; deep links optional) |
| M7 | Monetization (replaces PLAN “bottom banner ads”; rewarded + IAP + family sub) |
| M8 + polish | PLAN M6 (search/settings/store) |

PLAN.md status line still says “PROPOSED”; treat **DECISIONS.md** (stacks/caching/EPGTalk) plus **this file’s monetization section** as the approved product gate. Update PLAN.md / DECISIONS.md in a later docs commit so they no longer mention banner ads or “none in v1.”
