# AGENTS.md

## Product

Hisscore is a single Flutter app (retro Snake) in `Hisscore/`. There is no backend. Core play is local: move, eat, score, game over, local high score.

## Cursor Cloud specific instructions

Flutter SDK is a system toolchain, not a repo package. On this Cloud Agent image it is expected at `/opt/flutter` (Dockerfile) or `$HOME/sdk/flutter` if installed in the session. `flutter` must already be on `PATH` before `flutter pub get`.

Chrome/web is the supported E2E target here. Android SDK and iOS simulators are not required. Do not start Docker, databases, or Appwrite for this app.

Standard commands (also in `Hisscore/README.md`):

```bash
cd Hisscore
flutter pub get
flutter analyze
flutter test
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

The web-server process is a long-running `terminals` job, not an install step. After `flutter pub get`, a running web-server does not always pick up new packages until it is restarted.

`flutter run -d chrome` needs a display. Prefer `web-server` plus a browser against port 8080 in this environment.

Widget tests use Flutter's fake clock: `tester.pump(Duration)` advances Snake ticks (140ms each). The first apple is 4 cells ahead of the starting snake, so a score of `00010` appears after about 560ms of pumped time.
