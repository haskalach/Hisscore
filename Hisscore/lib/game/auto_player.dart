import 'snake_engine.dart';

/// Picks moves for the snake that plays itself behind the intro screen.
///
/// Deliberately simple: head toward the nearest food, never step
/// somewhere that kills it this tick, and prefer moves that leave room
/// to keep going. Good enough to look alive, cheap enough to run
/// alongside the menu.
abstract final class AutoPlayer {
  /// The direction the demo snake should take next, or null to carry on
  /// straight when nothing is safe.
  static Direction? chooseDirection(SnakeEngine engine) {
    final options = Direction.values
        .where((d) => d != engine.direction.opposite)
        .where((d) => _isSafe(engine, d))
        .toList();
    if (options.isEmpty) return null;

    final target = _nearestFood(engine);
    if (target == null) return options.first;

    options.sort((a, b) {
      // Closest to the food first; break ties by how much open space
      // the move leaves, so the snake doesn't trap itself as often.
      final byDistance = _distanceAfter(
        engine,
        a,
        target,
      ).compareTo(_distanceAfter(engine, b, target));
      if (byDistance != 0) return byDistance;
      return _freedomAfter(engine, b).compareTo(_freedomAfter(engine, a));
    });
    return options.first;
  }

  static GridPoint? _nearestFood(SnakeEngine engine) {
    if (engine.foods.isEmpty) return null;
    var best = engine.foods.first.position;
    var bestDistance = _distance(engine, engine.head, best);
    for (final food in engine.foods.skip(1)) {
      final distance = _distance(engine, engine.head, food.position);
      if (distance < bestDistance) {
        best = food.position;
        bestDistance = distance;
      }
    }
    return best;
  }

  static bool _isSafe(SnakeEngine engine, Direction direction) {
    final next = _step(engine, engine.head, direction);
    if (next == null) return false;
    if (engine.obstacles.contains(next)) return false;
    // The tail moves out of the way this tick unless the snake grows.
    final body = engine.snake.sublist(0, engine.snake.length - 1);
    return !body.contains(next);
  }

  /// Where a move lands, or null if it would leave the board on a mode
  /// that doesn't wrap.
  static GridPoint? _step(
    SnakeEngine engine,
    GridPoint from,
    Direction direction,
  ) {
    final next = from + direction.delta;
    final outside =
        next.x < 0 ||
        next.y < 0 ||
        next.x >= engine.columns ||
        next.y >= engine.rows;
    if (!outside) return next;
    if (!engine.wrapEnabled) return null;
    return GridPoint(
      ((next.x % engine.columns) + engine.columns) % engine.columns,
      ((next.y % engine.rows) + engine.rows) % engine.rows,
    );
  }

  static int _distanceAfter(
    SnakeEngine engine,
    Direction direction,
    GridPoint target,
  ) {
    final next = _step(engine, engine.head, direction);
    if (next == null) return 1 << 20;
    return _distance(engine, next, target);
  }

  /// How many safe cells sit next to where this move lands.
  static int _freedomAfter(SnakeEngine engine, Direction direction) {
    final next = _step(engine, engine.head, direction);
    if (next == null) return 0;
    var free = 0;
    for (final d in Direction.values) {
      final beyond = _step(engine, next, d);
      if (beyond == null) continue;
      if (engine.obstacles.contains(beyond)) continue;
      if (engine.snake.contains(beyond)) continue;
      free++;
    }
    return free;
  }

  /// Grid distance, taking the short way round when the board wraps.
  static int _distance(SnakeEngine engine, GridPoint a, GridPoint b) {
    var dx = (a.x - b.x).abs();
    var dy = (a.y - b.y).abs();
    if (engine.wrapEnabled) {
      dx = dx < engine.columns - dx ? dx : engine.columns - dx;
      dy = dy < engine.rows - dy ? dy : engine.rows - dy;
    }
    return dx + dy;
  }
}
