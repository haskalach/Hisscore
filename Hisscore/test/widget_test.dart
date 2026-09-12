import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/high_score_store.dart';
import 'package:hisscore/game/snake_engine.dart';
import 'package:hisscore/main.dart';
import 'package:hisscore/ui/board.dart';

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

    // First apple is 4 cells ahead; ticks are 240ms.
    await tester.pump(const Duration(milliseconds: 1100));
    final score = tester.widget<Text>(find.byKey(const Key('score-SCORE')));
    expect(score.data, '00010');
    final hi = tester.widget<Text>(find.byKey(const Key('score-HI')));
    expect(hi.data, '00010');
  });

  testWidgets('Up on the D-pad turns the snake before the next tick', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<SnakeBoardPainter>()
        .single;
    expect(painter.engine.direction, Direction.up);
    expect(painter.engine.head.y, lessThan(painter.engine.snake.last.y));
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
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('PLAY AGAIN'), findsOneWidget);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('PAUSE'), findsOneWidget);
    expect(find.text('00000'), findsWidgets);
  });

  testWidgets('mode selector appears on ready screen', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    // Mode selector should show the three modes.
    expect(find.text('CLASSIC'), findsOneWidget);
    expect(find.text('ADVENTURE'), findsOneWidget);
    expect(find.text('ENDLESS'), findsOneWidget);
    expect(find.text('SELECT MODE'), findsOneWidget);
  });

  testWidgets('can exit to menu to change mode from gameplay', (tester) async {
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
    expect(find.text('MENU'), findsOneWidget);

    // Tap MENU while running
    await tester.tap(find.text('MENU'));
    await tester.pump();

    // Returns to ready screen where mode selector is accessible
    expect(find.text('SELECT MODE'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });

  testWidgets('a slow drag on the board turns the snake', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    // A deliberate, slow drag — no flick velocity at all.
    await tester.drag(
      find.byType(SnakeBoard),
      const Offset(0, 40),
      touchSlopY: 0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(_painterOf(tester).engine.direction, Direction.down);
  });

  testWidgets('one gesture can chain two turns', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    // Down, then left, without lifting the finger.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SnakeBoard)),
    );
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.up();
    await tester.pump();

    final engine = _painterOf(tester).engine;
    expect(engine.inputQueue, [Direction.down, Direction.left]);

    await tester.pump(const Duration(milliseconds: 240));
    expect(engine.direction, Direction.down);
    await tester.pump(const Duration(milliseconds: 240));
    expect(engine.direction, Direction.left);
  });
}

SnakeBoardPainter _painterOf(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<SnakeBoardPainter>()
      .single;
}
