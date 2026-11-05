# Touch TV Guide — Android-first build plan

Branch: `claude/android`  
Status: **ready to execute one milestone at a time**  
Authority: follow `docs/DECISIONS.md` (owner-approved 2026-11-05). `docs/PLAN.md` remains the feasibility audit; where the two disagree, **DECISIONS wins**.

Goal: ship a usable Android app on top of the existing JVM `:core` module, then port to iOS. This document is the Android track only. Do **not** merge to `main` without owner approval.

---

## Pre-build / open questions (confirm before app code)

Do these before writing `:app` code. They are not blockers for scaffolding, but they are blockers for a public or store release.

| Item | Current decision (`docs/DECISIONS.md`) | What to confirm / do |
|---|---|---|
| **EPGTalk licensing** | Maintainer will **not** be contacted. Keep use **personal-scale and conservative**. | Treat as open risk for any non-personal release. Fetch only from the public feed URL (config), cache **on device**, refresh at most daily. Make the feed URL easy to swap. Do not redistribute EPGTalk data from our own host/CDN. |
| Caching | **On-device cache only.** No server-side mirror. | Stick to Room (+ optional raw XML file on disk). No GitHub Releases/Pages mirror. |
| Monetization | **None in v1.** | No AdMob / banner code. Ignore PLAN.md § ads risk for v1. |
| Feed window | EPGTalk US local ≈ **72 hours**, ~140 markets. | Bound right-arrow / day picker with `GuideLogic.dataEnd`. Do not hard-code 7 days. |
| Zip → market | Still needed (PLAN audit). | Bundle a static zip→DMA/market table (public-domain-derived). Verify source attribution before store. |
| Provider lineups | EPGTalk is market-based, not provider-lineup-based. | Setup: market + curated streaming providers; channel numbers from feed; user customization covers gaps. |
| Privacy / store | Coarse location only for zip; no accounts. | Short privacy policy required before Play listing (Milestone 7). |

**Already done (do not redo):**

- Shared Kotlin `:core` — `Models.kt`, `GuideLogic.kt`, `XmltvParser.kt`
- Unit tests — `core/src/test/kotlin/.../CoreTest.kt`
- Docs — `docs/DATA_MODEL.md`, `docs/DECISIONS.md`, `docs/PLAN.md`
- CI — `.github/workflows/android.yml` runs `gradle :core:test` on `claude/android`
- Root Gradle — `settings.gradle.kts` includes `:core` and notes `:app` as next; `build.gradle.kts` applies Kotlin JVM 2.0.21; `core/build.gradle.kts` is JVM 17

**Not in tree yet:** Gradle wrapper, `:app`, Android plugin, Compose, Room, networking, any UI.

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

**Why next:** First visible product surface. Until Milestone 5, use a debug default market / last-fetched data (or “open guide” with empty-state CTA).

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

## Milestone 7 — Store packaging

Only after M1–M6 are solid enough for a personal or closed test track. Respect EPGTalk **personal-scale** posture until licensing is clearer.

### Tasks

1. Application id, versionCode/versionName, release signing config (secrets via CI or local; never commit keystore).
2. ProGuard/R8 keep rules for Room / Kotlin if minify enabled.
3. Adaptive icon, label “Touch TV Guide”, theme colors/font-size settings if still required by spec (can be minimal).
4. Privacy policy URL (zip/location use, on-device cache, no accounts, data source disclosure).
5. Play Console listing: short/full description, screenshots, content rating, data safety form.
6. CI: `assembleRelease` (unsigned or with secrets); optional Play upload later.
7. Deep links to provider apps (optional, PLAN §11): package intents; best-effort.
8. Final pass: missing-data states, theme, font size, search polish from PLAN milestone 6.

### Reuse

- Entire `:app` + `:core` stack
- DECISIONS: no ads v1; no merge to `main` without approval

### Acceptance criteria

- [ ] Signed release (or Play internal testing) APK/AAB installs and completes setup → guide → reminder on a physical device.
- [ ] Privacy policy and data-safety answers match actual behavior (on-device only).
- [ ] No ad SDKs in the binary.
- [ ] Owner explicitly approves any PR to `main` and any public listing.

---

## Suggested working order (checklist)

```
Pre-build notes acknowledged (EPGTalk conservative use)
→ M1 Wrapper + :app scaffold + CI assembleDebug
→ M2 Room + repository + GuideLogic wiring
→ M3 Fetch + XmltvParser + WorkManager
→ M4 Compose guide grid (+ light customization)
→ M5 Setup / Home profile
→ M6 Reminders
→ M7 Store packaging / policy
→ (Later) iOS port from docs/DATA_MODEL.md + CoreTest cases on claude/ios
```

## Out of scope for this Android-first plan

- iOS implementation (separate track on `claude/ios` after Android is usable)
- Server-side EPG mirror / CDN
- Ads / IAP
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
| M7 + polish | PLAN M6 (search/settings/store) |

PLAN.md status line still says “PROPOSED”; treat **DECISIONS.md** as the approved gate for stacks, caching, monetization, and branch policy. Update PLAN.md status in a later docs commit if the owner wants the audit file marked approved.
