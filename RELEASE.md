# Release checklist

What's left before Hisscore can go on the Play Store and App Store, and
what's deliberately parked. Everything here is something the repo cannot
do for itself — it needs a device, an account, or a decision.

Last reviewed: 2026-09-12.

---

## Blocking submission

### 1. Play the APK on a real phone

**Nobody has verified four shipped features on real hardware.** The web
preview can't exercise any of them:

- [ ] **Sound** — eat blip, bonus, level-up, game-over, and the mute toggle
- [ ] **Share** — SHARE SCORE on the game-over screen should open the
      Android share sheet
- [ ] **Notifications** — finish a Daily Challenge; it should ask for
      permission, then schedule a streak reminder ~20h out
- [ ] **Rating prompt** — should fire once on a new high score, after a
      couple of games
- [ ] **Lifecycle** — background the app mid-run and come back; the run
      must be paused, not dead
- [ ] **Haptics** — button presses should buzz

Build one with:

```bash
cd Hisscore
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Or grab the artifact from any green CI run.

### 2. Privacy policy at a public URL

Both stores require a reachable policy even though the app collects
nothing. The page is written — [`docs/index.html`](docs/index.html) —
but is **not hosted yet and has a placeholder contact address**.

- [ ] Put a real support email in it (currently `support@hisscore.app`,
      clearly marked as a placeholder)
- [ ] Turn on GitHub Pages for this repo: Settings → Pages → Source →
      Deploy from branch → `main` / `/docs`
- [ ] Paste the resulting URL into Play Console and App Store Connect

The substance is short and already true: no accounts, no analytics, no
ads, no network calls; scores and stats live in local app storage;
uninstalling removes everything. The only permission the release build
requests is `POST_NOTIFICATIONS`, for the on-device streak reminder.

### 3. Upload keystore

`android/app/build.gradle.kts` already reads `android/key.properties`
when it exists and falls back to debug keys when it doesn't — so builds
work today but **cannot be published**.

- [ ] Create the keystore:
      ```bash
      keytool -genkey -v -keystore ~/upload-keystore.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload
      ```
- [ ] Write `android/key.properties` (gitignored — never commit it)
- [ ] **Back the keystore up somewhere you won't lose it.** Lose this
      file and you can never update the app under the same listing.
- [ ] Build with `flutter build appbundle` for Play

### 4. Screenshots

Must come from a real device — Play down-ranks listings whose
screenshots aren't real gameplay. Shot list and required sizes are in
[`store/listing.md`](store/listing.md).

- [ ] Mid-run with a long snake (the one that sells it)
- [ ] Intro screen
- [ ] Hardcore, obstacles visible
- [ ] Game over with the score breakdown
- [ ] Daily challenge card showing a streak
- [ ] *(optional)* HOW tab with the pickup legend

### 5. iOS has never been built

Not once, on any machine. The icons and launch screens were generated
and the bundle ID is set (`com.hisscore.hisscore`), but **nothing has
ever compiled**, so the whole platform is unverified.

- [ ] Build on a Mac and fix whatever falls out
- [ ] Check the plugin setup: `audioplayers`,
      `flutter_local_notifications` (needs push capability and permission
      strings), `in_app_review`
- [ ] Provisioning profile and App Store Connect record
- [ ] Capture 6.7" screenshots (1290×2796)

If iOS isn't actually a target, say so — the repo currently generates
iOS assets on every icon run for nothing.

---

## Worth doing, not blocking

### Pick a real crash reporter

`lib/game/crash_reporter.dart` is a seam with a local implementation:
errors are captured and the last 20 kept on-device, but **nothing is
sent anywhere**. You'll still be blind to crashes in the wild.

`SentryCrashReporter` (`lib/game/sentry_crash_reporter.dart`) is wired
up and used in `main.dart` when a DSN is supplied at build time — it
falls back to the local-only reporter otherwise, so this ships as a
no-op until a Sentry project exists.

- [ ] Create a Sentry project, get its DSN
- [ ] Build/run with
      `--dart-define=SENTRY_DSN=<your dsn>` (see `README`/`AGENTS.md`)
- [ ] Consider passing it through CI as a repo secret for release builds

### Store listing content

- [x] Title, descriptions, keywords, category, Data safety answers —
      [`store/listing.md`](store/listing.md)
- [x] Feature graphic 1024×500 — `store/feature-graphic.png`
- [x] Play listing icon 512×512 — `store/play-icon-512.png`
- [ ] Paste it all into Play Console / App Store Connect
- [ ] Content rating questionnaire
- [ ] Play Console Data safety form

---

## Parked deliberately

Not bugs — decisions with a reason to wait.

**Daily challenge boards differ across devices.** The grid follows the
screen, so a taller phone gets a taller board from the same seed. Only
matters if daily scores are ever compared between players; fixing it
means either letterboxing daily runs or pinning a fixed grid, both of
which cost something.

**Global leaderboard.** Needs a backend — Firebase Firestore with
anonymous auth is the low-effort path. The biggest single lever for
making the game competitive, and the main reason the daily-board issue
above would start to matter.

**Real push notifications.** Today's reminders are local and on-device.
Server-initiated re-engagement needs FCM plus APNs credentials.

**`game_page.dart` is still ~1,000 lines.** The presentational half was
split out; what remains is orchestration (engine lifecycle, ticker,
persistence, sound, notifications, share, daily, demo). Extracting a
`GameSession` controller is the obvious next step, but it's a tax rather
than a crisis.

**Golden tests for the board painter.** The engine and flows are well
covered; the rendering isn't. Two of the visual bugs this project has
hit — the malformed lightning bolt and the jagged star — were caught by
eye, not by a test.
