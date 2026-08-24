import 'dart:math';

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

/// Pure Snake rules: move, eat, grow, collide. No Flutter dependency.
class SnakeEngine {
  SnakeEngine({
    this.columns = 20,
    this.rows = 20,
    this.initialLength = 3,
    this.pointsPerFood = 10,
    this.initialTick = const Duration(milliseconds: 240),
    this.minTick = const Duration(milliseconds: 90),
    this.firstFoodDistance = 4,
    Random? random,
  }) : random = random ?? Random() {
    reset();
  }

  final int columns;
  final int rows;
  final int initialLength;
  final int pointsPerFood;
  final Duration initialTick;
  final Duration minTick;
  final int firstFoodDistance;
  final Random random;

  late List<GridPoint> snake;
  late GridPoint food;
  late Direction direction;
  Direction? queuedDirection;
  late GamePhase phase;
  late int score;
  late Duration tickInterval;
  int foodsEaten = 0;
  bool justAte = false;
  bool won = false;

  GridPoint get head => snake.first;

  void reset() {
    final startX = columns ~/ 2;
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
    food = _placeFirstFood();
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

  void tick() {
    if (phase != GamePhase.running) {
      return;
    }
    justAte = false;
    if (queuedDirection != null && queuedDirection != direction.opposite) {
      direction = queuedDirection!;
    }
    queuedDirection = null;

    final next = head + direction.delta;
    if (next.x < 0 || next.y < 0 || next.x >= columns || next.y >= rows) {
      phase = GamePhase.gameOver;
      return;
    }

    final eating = next == food;
    final bodyToCheck = eating ? snake : snake.sublist(0, snake.length - 1);
    if (bodyToCheck.contains(next)) {
      phase = GamePhase.gameOver;
      return;
    }

    snake = [next, ...snake];
    if (eating) {
      justAte = true;
      foodsEaten += 1;
      score += pointsPerFood;
      if (foodsEaten % 4 == 0) {
        final nextMs = (tickInterval.inMilliseconds - 12).clamp(
          minTick.inMilliseconds,
          initialTick.inMilliseconds,
        );
        tickInterval = Duration(milliseconds: nextMs);
      }
      final spawned = _spawnFood();
      if (spawned == null) {
        won = true;
        phase = GamePhase.gameOver;
      } else {
        food = spawned;
      }
    } else {
      snake.removeLast();
    }
  }

  GridPoint _placeFirstFood() {
    final target = GridPoint(head.x + firstFoodDistance, head.y);
    if (target.x < columns && !_occupies(target)) {
      return target;
    }
    return _spawnFood() ?? target;
  }

  bool _occupies(GridPoint point) => snake.contains(point);

  GridPoint? _spawnFood() {
    final empty = <GridPoint>[
      for (var y = 0; y < rows; y++)
        for (var x = 0; x < columns; x++)
          if (!_occupies(GridPoint(x, y))) GridPoint(x, y),
    ];
    if (empty.isEmpty) {
      return null;
    }
    return empty[random.nextInt(empty.length)];
  }
}
