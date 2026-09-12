# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working conventions

Keep output minimal — this burns real tokens:

- Don't dump full command output (`flutter test`, `flutter analyze`,
  `flutter build`, `git log`, etc.) into responses; run with `tail`/grep
  for the relevant lines, or just state pass/fail and the error if any.
- Don't paste full file contents back after a Read/Edit/Write unless the
  user needs to review them — the tool result already confirms the
  change.
- Summarize instead of narrating every tool call; report outcomes, not
  process.
- Prefer targeted `flutter test path/to/file.dart` over the whole suite
  while iterating; run the full suite once before considering something
  done.

## Product

Hisscore is a single Flutter app (retro Snake) that lives in `Hisscore/`.
There is no backend — everything is local: play, score, high scores,
crash log, and the daily-challenge streak all live in `SharedPreferences`
on-device.

## Commands

All commands run from the `Hisscore/` directory (CI's working directory
is also `Hisscore`, not the repo root).

```bash
cd Hisscore
flutter pub get                # install deps
flutter analyze                # static analysis (must be clean)
dart format --output=none --set-exit-if-changed .   # CI's formatting check
flutter test                   # full test suite
flutter test test/snake_engine_test.dart             # single file
flutter test test/snake_engine_test.dart --plain-name "some test name"  # single test
flutter run                    # a connected device
flutter run -d chrome          # web, with a display
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080   # headless web (Cursor Cloud, CI-like envs)
```

Regenerate generated, non-opaque-binary assets (icon, splash, sfx) after
touching `tool/generate_*.dart`:

```bash
dart run tool/generate_icon.dart      # assets/icon/*.png
dart run flutter_launcher_icons       # platform icon sets
dart run flutter_native_splash:create # launch screens
dart run tool/generate_sfx.dart       # assets/sfx/*.wav
```

`tool/generate_store_graphics.dart` builds the Play Store feature graphic
under `store/`; `tool/static_server.dart` is a tiny static file server
used to serve `build/web` locally (see `.claude/launch.json`).

Widget tests use Flutter's fake clock: `tester.pump(Duration)` advances
Snake ticks (240ms each by default). The first apple is 4 cells ahead of
the starting snake, so a score of `00010` appears after about 960ms of
pumped time.

### CI (`.github/workflows/ci.yaml`)

Three jobs on every push/PR: `analyze-and-test` (format check + analyze +
test), `build-android` (release APK, debug-signed — exists to catch
Gradle/resource-linking breakage that has slipped through when only web
was built), `build-web`. Flutter version is pinned via `FLUTTER_VERSION`
in the workflow env.

## Architecture

### Engine / UI split

`lib/game/snake_engine.dart` (`SnakeEngine`) is pure Dart with **no
Flutter dependency** — the whole ruleset (movement, collisions, food,
combos, power-ups, levels, obstacles, scoring) is one mutable class
driven by `tick()`, `queueTurn()`, `start()`, `pause()`. Widgets never
touch game rules directly; they read engine state and call these
methods. Tests exercise the engine directly without pumping widgets
(`test/snake_engine_test.dart`, `test/level_test.dart`), which is why
most game-logic tests don't need a `WidgetTester`.

Key engine details worth knowing before changing behavior:

- **Timing is deterministic**: `elapsedMs` is an in-game clock advanced
  by `tickInterval` each tick (never `DateTime.now()`), so combo/power-up
  windows (`comboWindowMs`, `speedBurstMs`, `magnetMs`,
  `bonusFoodLifetimeMs`) are fully testable with `tester.pump`.
- **Input buffering**: `inputQueue` holds up to `maxQueuedTurns` (2)
  pending turns so a fast L-turn isn't lost to a single per-tick slot.
- **`GameMode`** (`classic`/`adventure`/`endless`/`hardcore`/`zen`) gates
  wrap-around (`wrapEnabled`), invulnerability (`zen`), score multiplier
  (`hardcore` = 2x), and whether shields actually work (`shieldActive` is
  false in hardcore). Obstacle layouts come from `lib/game/level.dart`
  (`LevelData`) — adventure earns levels by apples eaten
  (`_checkLevelAdvance`), hardcore escalates its own "pseudo-level" every
  `hardcoreApplesPerStep` apples starting from `hardcoreStartLevel`
  (chosen to keep the snake's starting lane clear).
- **Food** (`lib/game/food_types.dart`, `FoodItem`/`FoodType`) is a list,
  not a single apple: there's always a primary apple
  (`_ensurePrimaryApple`) plus occasional timed bonus pickups (star,
  shield, speed, shrink, magnet) that despawn after
  `bonusFoodLifetimeMs`. `food` (singular) is a backward-compat getter
  for the primary apple's position.
- **Daily challenge** (`lib/game/daily_challenge.dart`) seeds the
  `Random` from the date so the board is reproducible per-day, but the
  grid is sized to the screen, so boards aren't comparable across
  differently-sized devices.
- **`AutoPlayer`** (`lib/game/auto_player.dart`) drives the engine
  autonomously — used for the attract-mode demo on the menu (see
  `game_page.dart`), not just tests.

### Storage seam

`lib/game/high_score_store.dart` defines `HighScoreStore` as an abstract
interface with two implementations: `SharedPreferencesHighScoreStore`
(production, requires `await init()` before use — see `main.dart`) and
`InMemoryHighScoreStore` (tests / previews). It holds four independent
concerns in one store: legacy single high score, top-5 leaderboard
(`ScoreEntry`), cumulative `GameStats`, and `DailyState` (streaks). Both
implementations must be kept in sync when adding a new persisted field.

### Crash reporting

`lib/game/crash_reporter.dart` defines the interface/implementation
pattern (`CrashReporter` → `LocalCrashReporter` / `NoopCrashReporter`);
`LocalCrashReporter` keeps the last N crashes in `SharedPreferences` so
there's always an on-device trace, independent of any off-device
reporter. `lib/game/sentry_crash_reporter.dart` adds `SentryCrashReporter`
(wraps `LocalCrashReporter` and also forwards to Sentry) plus
`initCrashReporting()`, which is opt-in: `main.dart` reads `SENTRY_DSN`
from `--dart-define` and only initializes Sentry when it's non-empty,
otherwise falling back to local-only reporting. `installCrashHandlers()`
is called first, before `runApp`, wiring both `FlutterError.onError` and
`PlatformDispatcher.instance.onError` to whichever reporter was chosen.

### UI layer

`lib/ui/game_page.dart` is the large top-level stateful widget
orchestrating game phases, mode/tab selection, sound, notifications, and
review prompts; it wires together `board.dart` (grid rendering),
`controls.dart` (swipe/keyboard input), `game_overlay.dart` (pause/game
over UI), `ready_tabs.dart` (mode picker), `hud_widgets.dart`,
`particles.dart`, `screen_shake.dart`, and `floating_label.dart` (score
popups). `lib/ui/theme.dart` holds the phosphor-green CRT retro palette
(`RetroColors`) shared across all UI. On the menu, the board underneath
plays itself via `AutoPlayer` until PLAY is pressed.

Other one-shot services: `lib/game/notification_service.dart` (local
daily-challenge streak reminder) and `lib/game/review_prompter.dart`
(in-app store review prompt, fires once on a new high score).

## Release process

Outstanding pre-launch work (device verification, store listings,
signing) is tracked in [RELEASE.md](RELEASE.md) — check there before
assuming a feature (sound, share, notifications, rating prompt, haptics)
has been verified on real hardware; the web preview can't exercise any
of them. Release (upload) signing uses a gitignored
`android/key.properties` pointing at a local keystore; debug-signed
builds work for sideloading but are rejected by the Play Store.
