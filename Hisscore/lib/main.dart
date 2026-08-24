import 'package:flutter/material.dart';

import 'game/high_score_store.dart';
import 'game/snake_engine.dart';
import 'ui/game_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
