import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/high_score_store.dart';
import 'package:hisscore/game/snake_engine.dart';
import 'package:hisscore/main.dart';

void main() {
  testWidgets('title cabinet shows HISCORE and PLAY', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    expect(find.text('HISCORE'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('PRESS START'), findsOneWidget);
    expect(find.text('00000'), findsWidgets);
  });

  testWidgets('PLAY starts the game and eating the first apple scores 10', (
    tester,
  ) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('PLAY'));
    await tester.pump();
    expect(find.text('PAUSE'), findsOneWidget);

    // First apple is 4 cells ahead; ticks are 140ms.
    await tester.pump(const Duration(milliseconds: 1100));
    final score = tester.widget<Text>(find.byKey(const Key('score-SCORE')));
    expect(score.data, '00010');
    final hi = tester.widget<Text>(find.byKey(const Key('score-HI')));
    expect(hi.data, '00010');
  });

  testWidgets('running into a wall shows GAME OVER and PLAY AGAIN restarts', (
    tester,
  ) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(
          columns: 6,
          rows: 6,
          firstFoodDistance: 1,
          random: Random(1),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('PAUSE'), findsOneWidget);
    expect(find.text('00000'), findsWidgets);
  });
}
