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
    // Endless mode so the snake can run past the window without dying.
    final game = engine(firstFoodDistance: 1, mode: GameMode.endless);
    game.start();
    game.tick(); // eats the apple one cell ahead
    expect(game.comboCount, 1);

    // Keep an apple on the board but well off the snake's row, and run
    // out the clock.
    final ticksNeeded =
        (SnakeEngine.comboWindowMs / game.tickInterval.inMilliseconds).ceil() +
        1;
    for (var i = 0; i < ticksNeeded; i++) {
      game.foods = [
        const FoodItem(position: GridPoint(19, 19), type: FoodType.apple),
      ];
      game.tick();
    }
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
    expect(game.magnetActive, isTrue);
    final apple = game.foods.firstWhere((f) => f.type == FoodType.apple);
    expect(apple.position.x, lessThan(farApple.x));
  });

  // ═══════════════════════════════════════════════════
  // New: input buffer
  // ═══════════════════════════════════════════════════

  test('queues two turns and applies them one per tick', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    game.queueTurn(Direction.up);
    game.queueTurn(Direction.left);
    expect(game.inputQueue, [Direction.up, Direction.left]);

    game.tick();
    expect(game.direction, Direction.up);
    game.tick();
    expect(game.direction, Direction.left);
    expect(game.inputQueue, isEmpty);
  });

  test('rejects a turn that reverses the already queued turn', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    game.queueTurn(Direction.up);
    game.queueTurn(Direction.down); // reverse of the queued turn
    expect(game.inputQueue, [Direction.up]);
  });

  test('ignores a repeat of the current heading', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    game.queueTurn(Direction.right); // already heading right
    expect(game.inputQueue, isEmpty);
  });

  test('never queues more than two turns', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    game.queueTurn(Direction.up);
    game.queueTurn(Direction.left);
    game.queueTurn(Direction.down);
    expect(game.inputQueue, hasLength(SnakeEngine.maxQueuedTurns));
  });

  // ═══════════════════════════════════════════════════
  // New: wall-clock timing
  // ═══════════════════════════════════════════════════

  test('combo window holds the same real time after the game speeds up', () {
    final slow = engine(firstFoodDistance: 20);
    slow.start();
    slow.tick();
    final slowTicks =
        (SnakeEngine.comboWindowMs / slow.tickInterval.inMilliseconds).ceil();

    // A faster engine needs proportionally more ticks for the same window.
    final fast = SnakeEngine(
      initialTick: const Duration(milliseconds: 120),
      random: Random(1),
    );
    fast.start();
    fast.tick();
    final fastTicks =
        (SnakeEngine.comboWindowMs / fast.tickInterval.inMilliseconds).ceil();

    expect(fastTicks, slowTicks * 2);
  });

  test('bonus food expires on elapsed time, not tick count', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    const bonus = FoodItem(
      position: GridPoint(18, 18),
      type: FoodType.star,
      spawnMs: 0,
      lifetimeMs: SnakeEngine.bonusFoodLifetimeMs,
    );
    expect(bonus.isExpired(SnakeEngine.bonusFoodLifetimeMs - 1), isFalse);
    expect(bonus.isExpired(SnakeEngine.bonusFoodLifetimeMs), isTrue);
  });

  test('engine clock advances by the tick interval', () {
    final game = engine(firstFoodDistance: 20);
    game.start();
    final step = game.tickInterval.inMilliseconds;
    game.tick();
    game.tick();
    expect(game.elapsedMs, step * 2);
  });

  // ═══════════════════════════════════════════════════
  // New: food spawn distance
  // ═══════════════════════════════════════════════════

  test('respawned food keeps its distance from the head', () {
    final game = engine(firstFoodDistance: 1);
    game.start();
    // Eat repeatedly; every respawn should land clear of the head.
    for (var i = 0; i < 30 && game.phase == GamePhase.running; i++) {
      for (final food in game.foods) {
        final dx = (food.position.x - game.head.x).abs();
        final dy = (food.position.y - game.head.y).abs();
        expect(
          dx > dy ? dx : dy,
          greaterThanOrEqualTo(1),
          reason: 'food should never spawn on the head',
        );
      }
      game.queueTurn(i.isEven ? Direction.down : Direction.right);
      game.tick();
    }
  });

  // ═══════════════════════════════════════════════════
  // New: hardcore obstacles
  // ═══════════════════════════════════════════════════

  test('hardcore starts with obstacles on the board', () {
    final game = engine(mode: GameMode.hardcore);
    expect(game.obstacles, isNotEmpty);
  });

  test('classic and zen stay obstacle-free', () {
    expect(engine(mode: GameMode.classic).obstacles, isEmpty);
    expect(engine(mode: GameMode.zen).obstacles, isEmpty);
  });

  test('hardcore obstacles never cover the snake', () {
    final game = engine(mode: GameMode.hardcore);
    for (final segment in game.snake) {
      expect(game.obstacles.contains(segment), isFalse);
    }
  });

  test('hardcore leaves the starting lane clear', () {
    final game = engine(mode: GameMode.hardcore);
    final startRow = game.head.y;
    // The snake starts heading right along this row — nothing may block
    // it before the player has a chance to turn.
    final blockers = game.obstacles.where((o) => o.y == startRow);
    expect(blockers, isEmpty);
  });

  test('food is never left buried under newly placed obstacles', () {
    final game = engine(mode: GameMode.adventure);
    game.start();
    // Run a while so levels advance and obstacle patterns change.
    for (var i = 0; i < 400 && game.phase == GamePhase.running; i++) {
      game.queueTurn(i % 4 == 0 ? Direction.down : Direction.right);
      game.tick();
      for (final food in game.foods) {
        expect(
          game.obstacles.contains(food.position),
          isFalse,
          reason: 'food should never sit inside an obstacle',
        );
      }
    }
  });
}

