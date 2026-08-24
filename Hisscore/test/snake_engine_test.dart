import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/snake_engine.dart';

void main() {
  SnakeEngine engine({
    int columns = 18,
    int rows = 18,
    int firstFoodDistance = 4,
    int seed = 1,
  }) {
    return SnakeEngine(
      columns: columns,
      rows: rows,
      firstFoodDistance: firstFoodDistance,
      random: Random(seed),
    );
  }

  test('starts ready with a 3-segment snake heading right', () {
    final game = engine();
    expect(game.phase, GamePhase.ready);
    expect(game.snake, hasLength(3));
    expect(game.direction, Direction.right);
    expect(game.score, 0);
    expect(game.food, GridPoint(game.head.x + 4, game.head.y));
  });

  test('eating the first apple grows the snake and awards 10 points', () {
    final game = engine();
    game.start();
    for (var i = 0; i < 4; i++) {
      game.tick();
    }
    expect(game.score, 10);
    expect(game.snake, hasLength(4));
    expect(game.justAte, isTrue);
    expect(game.phase, GamePhase.running);
  });

  test('moving without food keeps length the same', () {
    final game = engine(firstFoodDistance: 8);
    game.start();
    game.tick();
    expect(game.snake, hasLength(3));
    expect(game.score, 0);
    expect(game.head, GridPoint((18 ~/ 2) + 1, 18 ~/ 2));
  });

  test('ignores a reverse turn so the snake cannot fold into itself', () {
    final game = engine();
    game.start();
    game.queueTurn(Direction.left);
    game.tick();
    expect(game.direction, Direction.right);
  });

  test('queued 90-degree turn applies on the next tick', () {
    final game = engine();
    game.start();
    game.queueTurn(Direction.up);
    expect(game.direction, Direction.right);
    game.tick();
    expect(game.direction, Direction.up);
    expect(game.head.y, (18 ~/ 2) - 1);
  });

  test('hits a wall and ends the game', () {
    final game = engine(columns: 6, rows: 6, firstFoodDistance: 1);
    game.start();
    // Head starts at (3,3). Eat at (4,3), then (5,3), then out at (6,3).
    game.tick();
    game.tick();
    game.tick();
    expect(game.phase, GamePhase.gameOver);
  });

  test('self-collision ends the game', () {
    final game = SnakeEngine(
      columns: 8,
      rows: 8,
      initialLength: 5,
      firstFoodDistance: 6,
      random: Random(1),
    );
    game.start();
    game.queueTurn(Direction.up);
    game.tick();
    game.queueTurn(Direction.left);
    game.tick();
    game.queueTurn(Direction.down);
    game.tick();
    expect(game.phase, GamePhase.gameOver);
  });

  test('pause freezes ticks until resumed', () {
    final game = engine();
    game.start();
    final head = game.head;
    game.pause();
    game.tick();
    expect(game.head, head);
    expect(game.phase, GamePhase.paused);
    game.pause();
    game.tick();
    expect(game.head.x, head.x + 1);
  });

  test('start after game over resets score and snake', () {
    final game = engine(columns: 6, rows: 6, firstFoodDistance: 1);
    game.start();
    while (game.phase != GamePhase.gameOver) {
      game.tick();
    }
    expect(game.score, greaterThan(0));
    game.start();
    expect(game.phase, GamePhase.running);
    expect(game.score, 0);
    expect(game.snake, hasLength(3));
  });

  test('speed increases every four apples', () {
    final game = SnakeEngine(
      columns: 20,
      rows: 20,
      firstFoodDistance: 1,
      initialTick: const Duration(milliseconds: 140),
      random: Random(2),
    );
    game.start();
    var apples = 0;
    var guard = 0;
    while (apples < 4 && game.phase == GamePhase.running && guard < 400) {
      game.queueTurn(_towardFood(game));
      game.tick();
      if (game.justAte) {
        apples += 1;
      }
      guard += 1;
    }
    expect(apples, 4);
    expect(game.tickInterval, const Duration(milliseconds: 128));
  });
}

Direction _towardFood(SnakeEngine game) {
  final dx = game.food.x - game.head.x;
  final dy = game.food.y - game.head.y;
  final options = <Direction>[
    if (dx > 0) Direction.right,
    if (dx < 0) Direction.left,
    if (dy > 0) Direction.down,
    if (dy < 0) Direction.up,
  ];
  for (final direction in options) {
    if (direction != game.direction.opposite) {
      return direction;
    }
  }
  if (game.direction == Direction.left || game.direction == Direction.right) {
    return game.head.y > 0 ? Direction.up : Direction.down;
  }
  return game.head.x > 0 ? Direction.left : Direction.right;
}
