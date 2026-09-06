import 'dart:math';

import 'food_types.dart';
import 'level.dart';

// ─── Enums ──────────────────────────────────────────────

enum Direction {
  up,
  down,
  left,
  right;

  Direction get opposite => switch (this) {
    Direction.up => Direction.down,
    Direction.down => Direction.up,
    Direction.left => Direction.right,
    Direction.right => Direction.left,
  };

  GridPoint get delta => switch (this) {
    Direction.up => const GridPoint(0, -1),
    Direction.down => const GridPoint(0, 1),
    Direction.left => const GridPoint(-1, 0),
    Direction.right => const GridPoint(1, 0),
  };
}

enum GamePhase { ready, running, paused, gameOver }

enum GameMode {
  classic,
  adventure,
  endless;

  String get label => switch (this) {
    GameMode.classic => 'CLASSIC',
    GameMode.adventure => 'ADVENTURE',
    GameMode.endless => 'ENDLESS',
  };

  String get description => switch (this) {
    GameMode.classic => 'Original snake rules',
    GameMode.adventure => 'Levels with obstacles',
    GameMode.endless => 'Wrap walls, survive!',
  };
}

// ─── GridPoint ──────────────────────────────────────────

class GridPoint {
  const GridPoint(this.x, this.y);

  final int x;
  final int y;

  GridPoint operator +(GridPoint other) => GridPoint(x + other.x, y + other.y);

  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

// ─── SnakeEngine ────────────────────────────────────────

/// Pure Snake rules extended with game modes, power-ups, combos, and levels.
/// No Flutter dependency.
class SnakeEngine {
  SnakeEngine({
    this.columns = 20,
    this.rows = 20,
    this.initialLength = 3,
    this.pointsPerFood = 10,
    this.initialTick = const Duration(milliseconds: 240),
    this.minTick = const Duration(milliseconds: 90),
    this.firstFoodDistance = 4,
    this.mode = GameMode.classic,
    Random? random,
  }) : random = random ?? Random() {
    reset();
  }

  // ─── Configuration ────────────────────────────────

  final int columns;
  final int rows;
  final int initialLength;
  final int pointsPerFood;
  final Duration initialTick;
  final Duration minTick;
  final int firstFoodDistance;
  final Random random;
  GameMode mode;

  // ─── Game state ───────────────────────────────────

  late List<GridPoint> snake;
  late Direction direction;
  Direction? queuedDirection;
  late GamePhase phase;
  late int score;
  late Duration tickInterval;
  int foodsEaten = 0;
  bool justAte = false;
  bool won = false;

  // ─── Multi-food ───────────────────────────────────

  late List<FoodItem> foods;
  FoodItem? lastEatenFood;

  /// Backward-compatible: position of the primary apple.
  GridPoint get food => foods.isNotEmpty
      ? foods.first.position
      : GridPoint(columns ~/ 2, rows ~/ 2);

  // ─── Levels & obstacles ───────────────────────────

  int level = 1;
  int applesInLevel = 0;
  bool levelJustAdvanced = false;
  late Set<GridPoint> obstacles;

  // ─── Combo system ─────────────────────────────────

  static const int comboWindow = 8;
  int comboCount = 0;
  int ticksSinceLastEat = 0;
  int bestCombo = 0;

  double get comboMultiplier {
    if (comboCount <= 1) return 1.0;
    return 1.0 + (comboCount - 1) * 0.5;
  }

  // ─── Power-ups ────────────────────────────────────

  bool hasShield = false;
  bool speedBurstActive = false;
  int speedBurstTicksLeft = 0;

  // ─── Tick tracking ────────────────────────────────

  int totalTicks = 0;
  int totalApplesEaten = 0;

  // ─── Wrap mode ────────────────────────────────────

  bool get wrapEnabled => mode == GameMode.endless;

  // ─── Convenience ──────────────────────────────────

  GridPoint get head => snake.first;

  // ═══════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════

  void reset() {
    final startX = (initialLength - 1).clamp(1, columns - 1);
    final startY = rows ~/ 2;
    direction = Direction.right;
    queuedDirection = null;
    snake = [
      for (var i = 0; i < initialLength; i++) GridPoint(startX - i, startY),
    ];
    score = 0;
    foodsEaten = 0;
    justAte = false;
    won = false;
    tickInterval = initialTick;
    phase = GamePhase.ready;
    totalTicks = 0;
    totalApplesEaten = 0;

    // Combo
    comboCount = 0;
    ticksSinceLastEat = comboWindow + 1;
    bestCombo = 0;

    // Power-ups
    hasShield = false;
    speedBurstActive = false;
    speedBurstTicksLeft = 0;

    // Level
    level = 1;
    applesInLevel = 0;
    levelJustAdvanced = false;
    obstacles = _initialObstacles();

    // Food
    foods = [];
    lastEatenFood = null;
    foods.add(FoodItem(position: _placeFirstFood(), type: FoodType.apple));
  }

  void start() {
    if (phase == GamePhase.gameOver) {
      reset();
    }
    if (phase == GamePhase.ready || phase == GamePhase.paused) {
      phase = GamePhase.running;
    }
  }

  void pause() {
    if (phase == GamePhase.running) {
      phase = GamePhase.paused;
    } else if (phase == GamePhase.paused) {
      phase = GamePhase.running;
    }
  }

  /// Queue a 90-degree turn. Reverse directions are ignored.
  void queueTurn(Direction next) {
    if (next == direction.opposite) {
      return;
    }
    if (phase == GamePhase.ready) {
      queuedDirection = next;
      start();
      return;
    }
    if (phase == GamePhase.running) {
      queuedDirection = next;
    }
  }

  // ═══════════════════════════════════════════════════
  // Tick
  // ═══════════════════════════════════════════════════

  void tick() {
    if (phase != GamePhase.running) {
      return;
    }

    justAte = false;
    lastEatenFood = null;
    levelJustAdvanced = false;
    totalTicks++;
    ticksSinceLastEat++;

    // Apply queued direction.
    if (queuedDirection != null && queuedDirection != direction.opposite) {
      direction = queuedDirection!;
    }
    queuedDirection = null;

    // Calculate next head position.
    var next = head + direction.delta;

    // ── Wall handling ──
    if (next.x < 0 || next.y < 0 || next.x >= columns || next.y >= rows) {
      if (wrapEnabled) {
        next = _wrap(next);
      } else if (hasShield) {
        hasShield = false;
        next = _wrap(next);
      } else {
        phase = GamePhase.gameOver;
        return;
      }
    }

    // ── Obstacle collision ──
    if (obstacles.contains(next)) {
      if (hasShield) {
        hasShield = false;
      } else {
        phase = GamePhase.gameOver;
        return;
      }
    }

    // ── Check if eating ──
    final eatenIndex = foods.indexWhere((f) => f.position == next);
    final eating = eatenIndex >= 0;

    // ── Self-collision ──
    final bodyToCheck = eating ? snake : snake.sublist(0, snake.length - 1);
    if (bodyToCheck.contains(next)) {
      phase = GamePhase.gameOver;
      return;
    }

    // ── Move snake ──
    snake = [next, ...snake];

    if (eating) {
      final eaten = foods.removeAt(eatenIndex);
      lastEatenFood = eaten;
      justAte = true;
      _handleFoodEffect(eaten);

      // Ensure there's always a primary apple on the field.
      _ensurePrimaryApple();

      // Maybe spawn a bonus food.
      _maybeSpawnBonusFood();
    } else {
      snake.removeLast();
    }

    // ── Combo decay ──
    if (ticksSinceLastEat > comboWindow) {
      comboCount = 0;
    }

    // ── Speed burst countdown ──
    if (speedBurstActive) {
      speedBurstTicksLeft--;
      if (speedBurstTicksLeft <= 0) {
        speedBurstActive = false;
        _recalculateSpeed();
      }
    }

    // ── Despawn timed foods ──
    foods.removeWhere((f) => f.isExpired(totalTicks));

    // Ensure we always have at least one apple.
    _ensurePrimaryApple();
  }

  // ═══════════════════════════════════════════════════
  // Food effects
  // ═══════════════════════════════════════════════════

  void _handleFoodEffect(FoodItem eaten) {
    final shouldGrow = eaten.type.growsSnake;

    if (!shouldGrow) {
      // Remove the tail we just added (snake moved but shouldn't grow).
      if (snake.length > 1) snake.removeLast();
    }

    switch (eaten.type) {
      case FoodType.apple:
        foodsEaten++;
        totalApplesEaten++;
        applesInLevel++;
        final points = (pointsPerFood * comboMultiplier).round();
        score += points;
        _updateCombo();
        _checkSpeedIncrease();
        _checkLevelAdvance();

      case FoodType.star:
        final points = (50 * comboMultiplier).round();
        score += points;
        _updateCombo();

      case FoodType.shield:
        hasShield = true;
        score += 5;

      case FoodType.speedBurst:
        speedBurstActive = true;
        speedBurstTicksLeft = 12;
        score += 5;
        _recalculateSpeed();

      case FoodType.shrink:
        score += 15;
        for (var i = 0; i < 2 && snake.length > 2; i++) {
          snake.removeLast();
        }
    }
  }

  // ═══════════════════════════════════════════════════
  // Combo
  // ═══════════════════════════════════════════════════

  void _updateCombo() {
    if (ticksSinceLastEat <= comboWindow) {
      comboCount++;
    } else {
      comboCount = 1;
    }
    if (comboCount > bestCombo) {
      bestCombo = comboCount;
    }
    ticksSinceLastEat = 0;
  }

  // ═══════════════════════════════════════════════════
  // Speed
  // ═══════════════════════════════════════════════════

  void _checkSpeedIncrease() {
    if (foodsEaten % 4 == 0) {
      _recalculateSpeed();
    }
  }

  void _recalculateSpeed() {
    var baseMs = initialTick.inMilliseconds - (foodsEaten ~/ 4) * 12;
    baseMs = baseMs.clamp(minTick.inMilliseconds, initialTick.inMilliseconds);

    // Adventure mode speed multiplier.
    if (mode == GameMode.adventure) {
      final mult = LevelData.speedMultiplier(level);
      baseMs = (baseMs / mult).round().clamp(
        minTick.inMilliseconds,
        initialTick.inMilliseconds,
      );
    }

    // Speed burst doubles the speed.
    if (speedBurstActive) {
      baseMs = (baseMs * 0.5).round().clamp(
        (minTick.inMilliseconds * 0.5).round(),
        initialTick.inMilliseconds,
      );
    }

    tickInterval = Duration(milliseconds: baseMs);
  }

  // ═══════════════════════════════════════════════════
  // Levels (Adventure)
  // ═══════════════════════════════════════════════════

  void _checkLevelAdvance() {
    if (mode != GameMode.adventure) return;
    final required = LevelData.applesRequired(level);
    if (applesInLevel >= required) {
      level++;
      applesInLevel = 0;
      levelJustAdvanced = true;
      obstacles = LevelData.safeObstacles(
        LevelData.obstaclesForLevel(level, columns, rows),
        snake,
        columns,
        rows,
      );
      _recalculateSpeed();
    }
  }

  Set<GridPoint> _initialObstacles() {
    if (mode != GameMode.adventure) return {};
    return LevelData.safeObstacles(
      LevelData.obstaclesForLevel(1, columns, rows),
      [for (var i = 0; i < initialLength; i++) GridPoint((initialLength - 1) - i, rows ~/ 2)],
      columns,
      rows,
    );
  }

  // ═══════════════════════════════════════════════════
  // Food spawning
  // ═══════════════════════════════════════════════════

  void _ensurePrimaryApple() {
    final hasApple = foods.any((f) => f.type == FoodType.apple);
    if (!hasApple) {
      final pos = _spawnFood();
      if (pos == null) {
        won = true;
        phase = GamePhase.gameOver;
        return;
      }
      foods.insert(0, FoodItem(position: pos, type: FoodType.apple));
    }
  }

  void _maybeSpawnBonusFood() {
    if (foods.length >= 3) return;
    final chance = mode == GameMode.adventure
        ? 0.25 + level * 0.02
        : 0.18;
    if (random.nextDouble() >= chance) return;

    final types = [
      FoodType.star,
      FoodType.shield,
      FoodType.speedBurst,
      FoodType.shrink,
    ];
    final type = types[random.nextInt(types.length)];
    final pos = _spawnFood();
    if (pos != null) {
      foods.add(FoodItem(
        position: pos,
        type: type,
        spawnTick: totalTicks,
        lifetime: 25,
      ));
    }
  }

  GridPoint _placeFirstFood() {
    final target = GridPoint(head.x + firstFoodDistance, head.y);
    if (target.x < columns &&
        !_isOccupied(target) &&
        !obstacles.contains(target)) {
      return target;
    }
    return _spawnFood() ?? target;
  }

  bool _isOccupied(GridPoint point) =>
      snake.contains(point) ||
      foods.any((f) => f.position == point) ||
      obstacles.contains(point);

  GridPoint? _spawnFood() {
    final empty = <GridPoint>[
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++)
          if (!_isOccupied(GridPoint(x, y))) GridPoint(x, y),
    ];
    if (empty.isEmpty) {
      return null;
    }
    return empty[random.nextInt(empty.length)];
  }

  GridPoint _wrap(GridPoint p) {
    return GridPoint(
      ((p.x % columns) + columns) % columns,
      ((p.y % rows) + rows) % rows,
    );
  }
}
