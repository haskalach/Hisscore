import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/food_types.dart';
import 'package:hisscore/game/snake_engine.dart';

void main() {
  SnakeEngine engine({
    int columns = 20,
    int rows = 20,
    int firstFoodDistance = 4,
    int seed = 1,
    GameMode mode = GameMode.classic,
  }) {
    return SnakeEngine(
      columns: columns,
      rows: rows,
      firstFoodDistance: firstFoodDistance,
      random: Random(seed),
      mode: mode,
    );
  }

  test('starts ready with a 3-segment snake heading right', () {
    final game = engine();
    expect(game.phase, GamePhase.ready);
    expect(game.snake, hasLength(3));
    expect(game.direction, Direction.right);
    expect(game.score, 0);
    expect(game.head, const GridPoint(2, 10));
    expect(game.food, const GridPoint(6, 10));
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
    expect(game.head, const GridPoint(3, 10));
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
    expect(game.head.y, 9);
  });

  test('hits a wall and ends the game', () {
    final game = engine(columns: 6, rows: 6, firstFoodDistance: 1);
    game.start();
    var ticks = 0;
    while (game.phase != GamePhase.gameOver && ticks < 20) {
      game.tick();
      ticks += 1;
    }
    expect(game.phase, GamePhase.gameOver);
    expect(ticks, greaterThan(0));
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
    // Verify the speed formula directly by manually eating apples.
    final game = SnakeEngine(
      columns: 20,
      rows: 20,
      firstFoodDistance: 1,
      initialTick: const Duration(milliseconds: 140),
      random: Random(2),
    );
    game.start();

    // Eat first apple (1 cell ahead at firstFoodDistance=1).
    game.tick();
    expect(game.justAte, isTrue);
    // Speed doesn't change until 4 apples.
    expect(game.tickInterval, const Duration(milliseconds: 140));

    // Manually eat 3 more apples by placing food right in front of the head.
    for (var i = 0; i < 3; i++) {
      // Place an apple directly ahead.
      game.foods.clear();
      game.foods.add(FoodItem(
        position: GridPoint(game.head.x + 1, game.head.y),
        type: FoodType.apple,
      ));
      game.tick();
      expect(game.justAte, isTrue, reason: 'Apple ${i + 2} not eaten');
    }

    // After 4 apples, speed should have decreased by 12ms.
    expect(game.foodsEaten, 4);
    expect(game.tickInterval, const Duration(milliseconds: 128));
  });

  // ═══════════════════════════════════════════════════
  // New: Game modes
  // ═══════════════════════════════════════════════════

  test('classic mode: wall collision ends game', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.classic);
    game.start();
    // Head is at (2,2), move right → 3, 4, then wall.
    game.tick(); // (3,2)
    game.tick(); // (4,2)
    game.tick(); // wall
    expect(game.phase, GamePhase.gameOver);
  });

  test('endless mode: snake wraps around walls', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.endless);
    game.start();
    // Head at (2,2), move right.
    game.tick(); // (3,2)
    game.tick(); // (4,2)
    game.tick(); // wraps → (0,2)
    expect(game.phase, GamePhase.running);
    expect(game.head, const GridPoint(0, 2));
  });

  test('adventure mode starts with level 1 and no obstacles', () {
    final game = engine(mode: GameMode.adventure);
    expect(game.level, 1);
    expect(game.obstacles, isEmpty);
    expect(game.applesInLevel, 0);
  });

  // ═══════════════════════════════════════════════════
  // New: Multi-food & power-ups
  // ═══════════════════════════════════════════════════

  test('foods list always contains at least one apple', () {
    final game = engine();
    expect(game.foods, isNotEmpty);
    expect(game.foods.first.type, FoodType.apple);
  });

  test('shield allows passing through one wall', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.classic);
    game.start();
    game.hasShield = true;
    // Move right to the wall.
    game.tick(); // (3,2)
    game.tick(); // (4,2)
    game.tick(); // would hit wall, but shield wraps → (0,2)
    expect(game.phase, GamePhase.running);
    expect(game.hasShield, false);
    expect(game.head, const GridPoint(0, 2));
  });

  // ═══════════════════════════════════════════════════
  // New: Combo system
  // ═══════════════════════════════════════════════════

  test('eating food within combo window builds combo multiplier', () {
    final game = SnakeEngine(
      columns: 20,
      rows: 20,
      firstFoodDistance: 1,
      random: Random(42),
    );
    game.start();
    // Eat the first apple (1 tick away).
    game.tick();
    expect(game.justAte, isTrue);
    expect(game.comboCount, 1);
    expect(game.comboMultiplier, 1.0);
  });

  test('combo resets after window expires', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    // Move without eating for many ticks.
    for (var i = 0; i < 15; i++) {
      game.queueTurn(Direction.down);
      game.tick();
      game.queueTurn(Direction.right);
      game.tick();
      game.queueTurn(Direction.up);
      game.tick();
      game.queueTurn(Direction.right);
      game.tick();
      if (game.phase != GamePhase.running) break;
    }
    // Combo should stay at 0 since no food eaten in window.
    expect(game.comboCount, 0);
  });

  // ═══════════════════════════════════════════════════
  // New: Obstacles
  // ═══════════════════════════════════════════════════

  test('obstacle collision ends game in adventure mode', () {
    final game = engine(mode: GameMode.adventure);
    game.start();
    // Place an obstacle right in front of the snake.
    game.obstacles = {GridPoint(game.head.x + 1, game.head.y)};
    game.tick();
    expect(game.phase, GamePhase.gameOver);
  });

  test('shield protects from obstacle collision', () {
    final game = engine(mode: GameMode.adventure);
    game.start();
    game.hasShield = true;
    game.obstacles = {GridPoint(game.head.x + 1, game.head.y)};
    game.tick();
    expect(game.phase, GamePhase.running);
    expect(game.hasShield, false);
  });

  // ═══════════════════════════════════════════════════
  // New: Hardcore mode
  // ═══════════════════════════════════════════════════

  test('hardcore mode doubles apple points', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.hardcore);
    game.start();
    game.foods = [FoodItem(position: GridPoint(game.head.x + 1, game.head.y), type: FoodType.apple)];
    game.tick();
    expect(game.score, 20);
  });

  test('hardcore mode ignores shields on wall collision', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.hardcore);
    game.start();
    game.hasShield = true;
    for (var i = 0; i < 5; i++) {
      game.tick();
    }
    expect(game.phase, GamePhase.gameOver);
  });

  // ═══════════════════════════════════════════════════
  // New: Zen mode
  // ═══════════════════════════════════════════════════

  test('zen mode survives self-collision without ending', () {
    final game = engine(mode: GameMode.zen);
    game.start();
    // Force a self-collision: snake heading right, feed it a tight loop.
    game.queueTurn(Direction.up);
    game.tick();
    game.queueTurn(Direction.left);
    game.tick();
    game.queueTurn(Direction.down);
    game.tick();
    // Head now moves back into its own former path.
    game.tick();
    expect(game.phase, GamePhase.running);
  });

  test('zen mode wraps at walls instead of dying', () {
    final game = engine(columns: 5, rows: 5, firstFoodDistance: 10, mode: GameMode.zen);
    game.start();
    for (var i = 0; i < 5; i++) {
      game.tick();
    }
    expect(game.phase, GamePhase.running);
  });

  // ═══════════════════════════════════════════════════
  // New: Magnet power-up
  // ═══════════════════════════════════════════════════

  test('magnet pulls other food toward the head each tick', () {
    final game = engine(columns: 10, rows: 10, firstFoodDistance: 10);
    game.start();
    final farApple = GridPoint(game.head.x + 5, game.head.y);
    game.foods = [
      FoodItem(position: GridPoint(game.head.x + 1, game.head.y), type: FoodType.magnet),
      FoodItem(position: farApple, type: FoodType.apple),
    ];
    game.tick();
    expect(game.magnetTicksLeft, greaterThan(0));
    final apple = game.foods.firstWhere((f) => f.type == FoodType.apple);
    expect(apple.position.x, lessThan(farApple.x));
  });
}

