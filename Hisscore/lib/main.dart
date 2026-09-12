import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/crash_reporter.dart';
import 'game/high_score_store.dart';
import 'game/snake_engine.dart';
import 'ui/game_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch framework and async errors before anything else runs, so a
  // failure during startup still leaves a trace.
  installCrashHandlers(LocalCrashReporter());

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
