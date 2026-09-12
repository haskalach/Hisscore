import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/high_score_store.dart';
import 'package:hisscore/game/snake_engine.dart';
import 'package:hisscore/main.dart';
import 'package:hisscore/ui/board.dart';

void main() {
  // ═══════════════════════════════════════════════════
  // Intro screen
  // ═══════════════════════════════════════════════════

  testWidgets('intro shows the title and a way to start', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    expect(find.text('HISCORE'), findsOneWidget);
    expect(find.text('PRESS START'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });

  testWidgets('intro opens on the modes tab', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    expect(find.text('MODES'), findsOneWidget);
    expect(find.text('HOW'), findsOneWidget);
    expect(find.text('STATS'), findsOneWidget);
    expect(find.text('SELECT MODE'), findsOneWidget);
    expect(find.text('PICKUPS'), findsNothing);
  });

  testWidgets('HOW tab shows the pickup legend and controls', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    await tester.tap(find.text('HOW'));
    await tester.pump();

    expect(find.text('PICKUPS'), findsOneWidget);
    expect(find.text('CONTROLS'), findsOneWidget);
    expect(find.text('APPLE'), findsOneWidget);
    expect(find.text('SELECT MODE'), findsNothing);
  });

  testWidgets('STATS tab reports when there is nothing to show yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      HisscoreApp(highScoreStore: InMemoryHighScoreStore()),
    );
    await tester.pump();

    await tester.tap(find.text('STATS'));
    await tester.pump();

    expect(find.text('NO RUNS YET'), findsOneWidget);
  });

  // ═══════════════════════════════════════════════════
  // Entering and leaving the game
  // ═══════════════════════════════════════════════════

  testWidgets('PLAY leaves the intro for the full-screen game', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('PLAY'));
    await tester.pump();

    // The menu is gone and the in-game HUD is up.
    expect(find.text('PRESS START'), findsNothing);
    expect(find.text('SELECT MODE'), findsNothing);
    expect(find.byKey(const Key('score-SCORE')), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('eating the first apple scores 10', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    // First apple is 4 cells ahead; ticks are 240ms.
    await tester.pump(const Duration(milliseconds: 1100));
    final score = tester.widget<Text>(find.byKey(const Key('score-SCORE')));
    expect(score.data, '00010');
    final hi = tester.widget<Text>(find.byKey(const Key('score-HI')));
    expect(hi.data, '00010');
  });

  testWidgets('the pause button pauses and resume continues', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('MENU'), findsOneWidget);
    expect(_painterOf(tester).engine.phase, GamePhase.paused);

    await tester.tap(find.text('RESUME'));
    await tester.pump();
    expect(find.text('PAUSED'), findsNothing);
    expect(_painterOf(tester).engine.phase, GamePhase.running);
  });

  testWidgets('MENU returns to the intro', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('MENU'));
    await tester.pump();

    expect(find.text('PRESS START'), findsOneWidget);
    expect(find.text('SELECT MODE'), findsOneWidget);
  });

  testWidgets('running into a wall ends the run and PLAY AGAIN restarts', (
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
    expect(find.text('SHARE SCORE'), findsOneWidget);

    await tester.tap(find.text('PLAY AGAIN'));
    await tester.pump();
    expect(find.text('GAME OVER'), findsNothing);
    expect(_painterOf(tester).engine.phase, GamePhase.running);
  });

  // ═══════════════════════════════════════════════════
  // Gesture and keyboard controls
  // ═══════════════════════════════════════════════════

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

  testWidgets('arrow keys still steer the snake', (tester) async {
    await tester.pumpWidget(
      HisscoreApp(
        highScoreStore: InMemoryHighScoreStore(),
        engineFactory: () => SnakeEngine(random: Random(1)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PLAY'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(_painterOf(tester).engine.direction, Direction.up);
  });

  // ═══════════════════════════════════════════════════
  // Grid sizing
  // ═══════════════════════════════════════════════════

  test('the play grid takes the shape of the screen', () {
    // Portrait phone: 20 across, taller than it is wide.
    final portrait = boardGridFor(const Size(390, 844));
    expect(portrait.columns, 20);
    expect(portrait.rows, greaterThan(portrait.columns));

    // Landscape flips it.
    final landscape = boardGridFor(const Size(844, 390));
    expect(landscape.rows, 20);
    expect(landscape.columns, greaterThan(landscape.rows));

    // A square window stays square.
    final square = boardGridFor(const Size(500, 500));
    expect(square.columns, square.rows);

    // A degenerate size still returns something playable.
    final empty = boardGridFor(Size.zero);
    expect(empty.columns, greaterThan(0));
    expect(empty.rows, greaterThan(0));
  });
}

SnakeBoardPainter _painterOf(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<SnakeBoardPainter>()
      .last;
}
