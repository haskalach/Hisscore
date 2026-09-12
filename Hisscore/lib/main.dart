import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/crash_reporter.dart';
import 'game/high_score_store.dart';
import 'game/sentry_crash_reporter.dart';
import 'game/snake_engine.dart';
import 'ui/game_page.dart';
import 'ui/theme.dart';

/// Off-device crash reporting is opt-in at build time — no DSN means
/// [initCrashReporting] falls back to the on-device-only reporter, so a
/// plain `flutter run` never talks to Sentry.
/// `flutter run --dart-define=SENTRY_DSN=<your dsn>` to enable it.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  await initCrashReporting(dsn: _sentryDsn, runWithReporter: _runApp);
}

Future<void> _runApp(CrashReporter reporter) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch framework and async errors before anything else runs, so a
  // failure during startup still leaves a trace.
  installCrashHandlers(reporter);

  // The play grid is shaped to the screen when a run starts, so turning
  // the device mid-game would paint a tall grid into a wide box and
  // stretch every cell. Portrait is the game's shape anyway.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final store = SharedPreferencesHighScoreStore();
  await store.init();
  runApp(HisscoreApp(highScoreStore: store));
}

class HisscoreApp extends StatelessWidget {
  const HisscoreApp({
    super.key,
    required this.highScoreStore,
    this.engineFactory,
  });

  final HighScoreStore highScoreStore;
  final SnakeEngine Function()? engineFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HISCORE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: RetroColors.voidBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: RetroColors.phosphor,
          brightness: Brightness.dark,
        ),
      ),
      home: GamePage(
        highScoreStore: highScoreStore,
        engineFactory: engineFactory,
      ),
    );
  }
}
