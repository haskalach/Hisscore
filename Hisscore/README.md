# HISCORE

Retro Snake in Flutter — phosphor-green CRT, five modes, and a daily
challenge. The menu shows the game playing itself; pressing PLAY hands
the whole screen over to the board.

## Run it

```bash
cd Hisscore
flutter pub get
flutter run                    # a connected device
flutter run -d chrome          # web
```

## Playing

- **Swipe or drag** anywhere on the board to turn. One continuous
  gesture can chain turns, and two are buffered, so a fast L-turn keeps
  both inputs.
- **Arrow keys / WASD** on desktop. `P` or `Esc` pauses, `M` returns to
  the menu.
- **Pause** is the button in the top-right of the HUD. Android's back
  gesture pauses a run, leaves a paused or finished one, and only closes
  the app from the menu.

The grid takes the shape of the screen — 20 columns and as many rows as
the device is tall — so the board fills the display with square cells.

### Modes

| Mode | Rules |
| --- | --- |
| Classic | Walls kill. The original. |
| Adventure | Levels with obstacle patterns that escalate as you clear apples. |
| Endless | Walls wrap. |
| Hardcore | Obstacles from the start, faster, double points, and shields don't save you. |
| Zen | Nothing kills you. Doesn't count toward the high score or leaderboard. |

### Pickups

Apples grow the snake and score. Bonus pickups appear for a few seconds
at a time: **star** (big points), **shield** (survive one crash),
**speed** (brief burst), **shrink** (lose two segments), **magnet**
(pulls food toward you). Chaining apples quickly builds a combo
multiplier.

### Daily challenge

One board per day, seeded from the date, with a streak for consecutive
days. Finishing one schedules a local reminder for the next day.

Note: the grid follows the screen, so two differently-sized phones don't
get an identical daily board. That only matters if daily scores are ever
compared across devices.

## Checks

```bash
cd Hisscore
flutter analyze
flutter test
```

## Regenerating assets

The app icon, launch splash and sound effects are generated from code,
not committed as opaque binaries:

```bash
dart run tool/generate_icon.dart      # assets/icon/*.png
dart run flutter_launcher_icons       # platform icon sets
dart run flutter_native_splash:create # launch screens
dart run tool/generate_sfx.dart       # assets/sfx/*.wav
```

## Release builds

`flutter build apk --release` works out of the box but signs with debug
keys — fine for sideloading, rejected by the Play Store.

For a real upload build, create a keystore and point the build at it:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then write `android/key.properties` (gitignored, never commit it):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<absolute path to upload-keystore.jks>
```

The build picks it up automatically. Prefer `flutter build appbundle`
for the Play Store; `--split-per-abi` gives smaller APKs for sideloading.
