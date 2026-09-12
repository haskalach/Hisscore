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
  endless,
  hardcore,
  zen;

  String get label => switch (this) {
    GameMode.classic => 'CLASSIC',
    GameMode.adventure => 'ADVENTURE',
    GameMode.endless => 'ENDLESS',
    GameMode.hardcore => 'HARDCORE',
    GameMode.zen => 'ZEN',
  };

  String get description => switch (this) {
    GameMode.classic => 'Original snake rules',
    GameMode.adventure => 'Levels with obstacles',
    GameMode.endless => 'Wrap walls, survive!',
    GameMode.hardcore => 'No shields. 2x points. Deadly.',
    GameMode.zen => 'No game over. Just vibes.',
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

  /// Where each segment sat before the current tick. The UI lerps
  /// between this and [snake] so the snake glides instead of jumping
  /// a whole cell every tick.
  late List<GridPoint> previousSnake;

  late Direction direction;

  /// Pending turns, applied one per tick. Two slots deep so a quick
  /// L-turn (up, then left) keeps both inputs instead of the second
  /// overwriting the first.
  final List<Direction> inputQueue = [];

  /// The turn that will be applied on the next tick, if any.
  Direction? get queuedDirection =>
      inputQueue.isEmpty ? null : inputQueue.first;

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

  /// How long a combo stays alive, in milliseconds rather than ticks:
  /// tied to ticks it would silently shrink as the game speeds up,
  /// making combos hardest exactly when the snake is longest.
  static const int comboWindowMs = 1920;
  int comboCount = 0;
  int lastEatMs = -comboWindowMs - 1;
  int bestCombo = 0;

  /// Whether a fresh apple would extend the current combo.
  bool get comboAlive => elapsedMs - lastEatMs <= comboWindowMs;

  double get comboMultiplier {
    if (comboCount <= 1) return 1.0;
    return 1.0 + (comboCount - 1) * 0.5;
  }

  // ─── Power-ups ────────────────────────────────────

  /// Power-up durations, in milliseconds for the same reason as
  /// [comboWindowMs].
  static const int speedBurstMs = 2880;
  static const int magnetMs = 4800;

  bool hasShield = false;
  int speedBurstUntilMs = 0;
  int magnetUntilMs = 0;

  bool get speedBurstActive => elapsedMs < speedBurstUntilMs;
  bool get magnetActive => elapsedMs < magnetUntilMs;

  /// Whether shields can currently save the snake. Hardcore mode makes
  /// shields purely cosmetic/score fodder — nothing stops a crash.
  bool get shieldActive => hasShield && mode != GameMode.hardcore;

  // ─── Tick tracking ────────────────────────────────

  int totalTicks = 0;
  int totalApplesEaten = 0;

  /// In-game clock, advanced by [tickInterval] on every tick. Keeps all
  /// timed mechanics on wall-clock durations while staying fully
  /// deterministic for tests (no DateTime).
  int elapsedMs = 0;

  // ─── Wrap mode ────────────────────────────────────

  bool get wrapEnabled => mode == GameMode.endless || mode == GameMode.zen;

  /// Zen mode never ends the run on a collision — the snake just
  /// glides through itself and any obstacle.
  bool get isInvulnerable => mode == GameMode.zen;

  /// Score multiplier applied to every point gain. Hardcore doubles
  /// the risk/reward.
  double get scoreMultiplier => mode == GameMode.hardcore ? 2.0 : 1.0;

  // ─── Convenience ──────────────────────────────────

  GridPoint get head => snake.first;

  // ═══════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════

  void reset() {
    final startX = (initialLength - 1).clamp(1, columns - 1);
    final startY = rows ~/ 2;
    direction = Direction.right;
    inputQueue.clear();
    snake = [
      for (var i = 0; i < initialLength; i++) GridPoint(startX - i, startY),
    ];
    previousSnake = List.of(snake);
    score = 0;
    foodsEaten = 0;
    justAte = false;
    won = false;
    tickInterval = initialTick;
    phase = GamePhase.ready;
    totalTicks = 0;
    totalApplesEaten = 0;
    elapsedMs = 0;

    // Combo
    comboCount = 0;
    lastEatMs = -comboWindowMs - 1;
    bestCombo = 0;

    // Power-ups
    hasShield = false;
    speedBurstUntilMs = 0;
    magnetUntilMs = 0;

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

  /// Queue a 90-degree turn, up to [maxQueuedTurns] deep.
  ///
  /// Each turn is checked against the direction the snake will actually
  /// be travelling when it lands — the last queued turn if one is
  /// pending, otherwise the current heading — so a buffered L-turn
  /// works but a reverse is still rejected.
  static const int maxQueuedTurns = 2;

  void queueTurn(Direction next) {
    final reference = inputQueue.isNotEmpty ? inputQueue.last : direction;
    if (next == reference || next == reference.opposite) {
      return;
    }
    if (phase == GamePhase.ready) {
      inputQueue.add(next);
      start();
      return;
    }
    if (phase == GamePhase.running && inputQueue.length < maxQueuedTurns) {
      inputQueue.add(next);
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
    elapsedMs += tickInterval.inMilliseconds;
    previousSnake = List.of(snake);

    // Apply the next queued turn.
    if (inputQueue.isNotEmpty) {
      final next = inputQueue.removeAt(0);
      if (next != direction.opposite) {
        direction = next;
      }
    }

    // Calculate next head position.
    var next = head + direction.delta;

    // ── Wall handling ──
    if (next.x < 0 || next.y < 0 || next.x >= columns || next.y >= rows) {
      if (wrapEnabled) {
        next = _wrap(next);
      } else if (shieldActive) {
        hasShield = false;
        next = _wrap(next);
      } else {
        phase = GamePhase.gameOver;
        return;
      }
    }

    // ── Obstacle collision ──
    if (obstacles.contains(next)) {
      if (isInvulnerable) {
        // Pass straight through.
      } else if (shieldActive) {
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
    if (!isInvulnerable && bodyToCheck.contains(next)) {
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
    if (!comboAlive) {
      comboCount = 0;
    }

    // ── Speed burst expiry ──
    if (speedBurstUntilMs > 0 && !speedBurstActive) {
      speedBurstUntilMs = 0;
      _recalculateSpeed();
    }

    // ── Despawn timed foods ──
    foods.removeWhere((f) => f.isExpired(elapsedMs));

    // ── Magnet pull ──
    _applyMagnet();

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
        final points = (pointsPerFood * comboMultiplier * scoreMultiplier)
            .round();
        score += points;
        _updateCombo();
        _checkSpeedIncrease();
        _checkLevelAdvance();
        _checkHardcoreObstacles();

      case FoodType.star:
        final points = (50 * comboMultiplier * scoreMultiplier).round();
        score += points;
        _updateCombo();

      case FoodType.shield:
        hasShield = true;
        score += (5 * scoreMultiplier).round();

      case FoodType.speedBurst:
        speedBurstUntilMs = elapsedMs + speedBurstMs;
        score += (5 * scoreMultiplier).round();
        _recalculateSpeed();

      case FoodType.shrink:
        score += (15 * scoreMultiplier).round();
        for (var i = 0; i < 2 && snake.length > 2; i++) {
          snake.removeLast();
        }

      case FoodType.magnet:
        magnetUntilMs = elapsedMs + magnetMs;
        score += (10 * scoreMultiplier).round();
    }
  }

  // ═══════════════════════════════════════════════════
  // Combo
  // ═══════════════════════════════════════════════════

  void _updateCombo() {
    if (comboAlive) {
      comboCount++;
    } else {
      comboCount = 1;
    }
    if (comboCount > bestCombo) {
      bestCombo = comboCount;
    }
    lastEatMs = elapsedMs;
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

    // Hardcore mode: always a little faster.
    if (mode == GameMode.hardcore) {
      baseMs = (baseMs * 0.85).round().clamp(
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
      _clearBuriedFood();
      _recalculateSpeed();
    }
  }

  /// Obstacles just moved. Anything they landed on top of can never be
  /// reached again, so clear it and let a fresh apple spawn.
  void _clearBuriedFood() {
    foods.removeWhere((f) => obstacles.contains(f.position));
    _ensurePrimaryApple();
  }

  Set<GridPoint> _initialObstacles() {
    // Adventure starts clean and earns its obstacles by level; hardcore
    // opens with them already on the board.
    final startLevel = switch (mode) {
      GameMode.adventure => 1,
      GameMode.hardcore => hardcoreStartLevel,
      _ => null,
    };
    if (startLevel == null) return {};
    return LevelData.safeObstacles(
      LevelData.obstaclesForLevel(startLevel, columns, rows),
      [
        for (var i = 0; i < initialLength; i++)
          GridPoint((initialLength - 1) - i, rows ~/ 2),
      ],
      columns,
      rows,
    );
  }

  // ═══════════════════════════════════════════════════
  // Obstacles (Hardcore)
  // ═══════════════════════════════════════════════════

  /// Hardcore has no levels, so its obstacles escalate on apples eaten:
  /// it opens on [hardcoreStartLevel]'s layout and moves up a pattern
  /// every [hardcoreApplesPerStep] apples.
  ///
  /// Level 7 (corner blocks) is the opener because it keeps the centre
  /// row clear — the snake starts there heading right, and a pattern
  /// across that lane would kill it before it could react.
  static const int hardcoreStartLevel = 7;
  static const int hardcoreApplesPerStep = 8;

  void _checkHardcoreObstacles() {
    if (mode != GameMode.hardcore) return;
    if (totalApplesEaten == 0 ||
        totalApplesEaten % hardcoreApplesPerStep != 0) {
      return;
    }
    final pseudoLevel =
        hardcoreStartLevel + totalApplesEaten ~/ hardcoreApplesPerStep;
    obstacles = LevelData.safeObstacles(
      LevelData.obstaclesForLevel(pseudoLevel, columns, rows),
      snake,
      columns,
      rows,
    );
    _clearBuriedFood();
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
    final chance = mode == GameMode.adventure ? 0.25 + level * 0.02 : 0.18;
    if (random.nextDouble() >= chance) return;

    final types = [
      FoodType.star,
      FoodType.shield,
      FoodType.speedBurst,
      FoodType.shrink,
      FoodType.magnet,
    ];
    final type = types[random.nextInt(types.length)];
    final pos = _spawnFood();
    if (pos != null) {
      foods.add(
        FoodItem(
          position: pos,
          type: type,
          spawnMs: elapsedMs,
          lifetimeMs: bonusFoodLifetimeMs,
        ),
      );
    }
  }

  /// How long a bonus pickup stays on the board.
  static const int bonusFoodLifetimeMs = 6000;

  /// Food never spawns right on top of the player: closer than this many
  /// cells (Chebyshev) to the head is free points, or a combo handed out
  /// by luck instead of steering.
  static const int minSpawnDistance = 3;

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
    // Prefer cells a fair distance from the head; fall back to anywhere
    // free once the board is too crowded to be choosy.
    final farEnough = empty.where(_isFarFromHead).toList();
    final candidates = farEnough.isEmpty ? empty : farEnough;
    return candidates[random.nextInt(candidates.length)];
  }

  bool _isFarFromHead(GridPoint point) {
    final dx = (point.x - head.x).abs();
    final dy = (point.y - head.y).abs();
    return (dx > dy ? dx : dy) >= minSpawnDistance;
  }

  // ═══════════════════════════════════════════════════
  // Magnet
  // ═══════════════════════════════════════════════════

  /// Pulls every food item one grid step toward the head, once per
  /// tick, while [magnetActive]. Never pulls a food onto the snake, an
  /// obstacle, or another food.
  void _applyMagnet() {
    if (!magnetActive) return;
    foods = [for (final f in foods) _magnetStep(f)];
  }

  FoodItem _magnetStep(FoodItem item) {
    final pos = item.position;
    final dx = (head.x - pos.x).clamp(-1, 1);
    final dy = (head.y - pos.y).clamp(-1, 1);
    if (dx == 0 && dy == 0) return item;

    final next = GridPoint(pos.x + dx, pos.y + dy);
    final blocked =
        snake.contains(next) ||
        obstacles.contains(next) ||
        foods.any((other) => !identical(other, item) && other.position == next);
    if (blocked) return item;

    return FoodItem(
      position: next,
      type: item.type,
      spawnMs: item.spawnMs,
      lifetimeMs: item.lifetimeMs,
    );
  }

  GridPoint _wrap(GridPoint p) {
    return GridPoint(
      ((p.x % columns) + columns) % columns,
      ((p.y % rows) + rows) % rows,
    );
  }
}
