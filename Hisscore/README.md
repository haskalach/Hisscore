# HISCORE

Retro Snake in Flutter. Eat apples, grow, and chase a high score on a CRT-style cabinet.

## Play

```bash
cd Hisscore
flutter pub get
flutter run -d chrome          # web
flutter run -d linux           # desktop
flutter run                    # pick a connected device
```

Cloud / headless web server:

```bash
cd Hisscore
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Then open `http://localhost:8080`.

## Controls

- Arrow keys or WASD
- Swipe on the board
- On-screen D-pad
- Space / Enter to start, pause, or restart
- P or Escape to pause

The first apple always spawns a few cells in front of the snake so a new game is easy to start.

## Checks

```bash
cd Hisscore
flutter analyze
flutter test
```

High scores are stored locally with `shared_preferences`.
