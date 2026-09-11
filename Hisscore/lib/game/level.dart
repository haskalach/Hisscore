import 'snake_engine.dart';

/// Provides obstacle layouts for each level in Adventure mode.
abstract final class LevelData {
  /// Number of apples required to advance from the given [level].
  static int applesRequired(int level) => 5 + level;

  /// Speed multiplier for the given [level] (higher = faster).
  static double speedMultiplier(int level) => 1.0 + (level - 1) * 0.06;

  /// Returns the set of obstacle grid points for a given [level].
  /// Levels 1–3 have no obstacles. From level 4 onward patterns increase.
  static Set<GridPoint> obstaclesForLevel(int level, int cols, int rows) {
    return switch (level) {
      <= 3 => <GridPoint>{},
      4 => _horizontalBar(cols, rows),
      5 => _verticalBar(cols, rows),
      6 => _cross(cols, rows),
      7 => _cornerBlocks(cols, rows),
      8 => _twoHorizontalBars(cols, rows),
      9 => _diamond(cols, rows),
      10 => _zigzag(cols, rows),
      11 => _spiral(cols, rows),
      _ => _maze(level, cols, rows),
    };
  }

  // ─── Level 4: Horizontal bar in the center ───

  static Set<GridPoint> _horizontalBar(int cols, int rows) {
    final cy = rows ~/ 2;
    final start = cols ~/ 4;
    final end = cols - cols ~/ 4;
    return {for (var x = start; x < end; x++) GridPoint(x, cy)};
  }

  // ─── Level 5: Vertical bar in the center ───

  static Set<GridPoint> _verticalBar(int cols, int rows) {
    final cx = cols ~/ 2;
    final start = rows ~/ 4;
    final end = rows - rows ~/ 4;
    return {for (var y = start; y < end; y++) GridPoint(cx, y)};
  }

  // ─── Level 6: Plus/cross in the center ───

  static Set<GridPoint> _cross(int cols, int rows) {
    return {..._horizontalBar(cols, rows), ..._verticalBar(cols, rows)};
  }

  // ─── Level 7: Four 2x2 blocks near corners ───

  static Set<GridPoint> _cornerBlocks(int cols, int rows) {
    final inset = 4;
    final points = <GridPoint>{};
    for (final origin in [
      GridPoint(inset, inset),
      GridPoint(cols - inset - 2, inset),
      GridPoint(inset, rows - inset - 2),
      GridPoint(cols - inset - 2, rows - inset - 2),
    ]) {
      for (var dx = 0; dx < 2; dx++) {
        for (var dy = 0; dy < 2; dy++) {
          points.add(GridPoint(origin.x + dx, origin.y + dy));
        }
      }
    }
    return points;
  }

  // ─── Level 8: Two parallel horizontal bars ───

  static Set<GridPoint> _twoHorizontalBars(int cols, int rows) {
    final y1 = rows ~/ 3;
    final y2 = rows * 2 ~/ 3;
    final start = cols ~/ 5;
    final end = cols - cols ~/ 5;
    return {
      for (var x = start; x < end; x++) ...[GridPoint(x, y1), GridPoint(x, y2)],
    };
  }

  // ─── Level 9: Diamond shape in center ───

  static Set<GridPoint> _diamond(int cols, int rows) {
    final cx = cols ~/ 2;
    final cy = rows ~/ 2;
    final size = 3;
    final points = <GridPoint>{};
    for (var d = 0; d <= size; d++) {
      points.addAll([
        GridPoint(cx + d, cy - size + d),
        GridPoint(cx - d, cy - size + d),
        GridPoint(cx + d, cy + size - d),
        GridPoint(cx - d, cy + size - d),
      ]);
    }
    return points;
  }

  /// Fills an axis-aligned rectangle of grid cells (clipped to a safe
  /// inset from the board edge). Used to build blocky, solid obstacle
  /// shapes instead of thin one-cell lines.
  static void _fillRect(Set<GridPoint> points, int x, int y, int w, int h) {
    for (var dx = 0; dx < w; dx++) {
      for (var dy = 0; dy < h; dy++) {
        points.add(GridPoint(x + dx, y + dy));
      }
    }
  }

  // ─── Level 10: Zigzag of solid blocks ───

  /// A staircase of solid rectangular blocks alternating high and low,
  /// like brick chunks stepping across the board.
  static Set<GridPoint> _zigzag(int cols, int rows) {
    final points = <GridPoint>{};
    const blockW = 3;
    const blockH = 3;
    final amplitude = (rows ~/ 5).clamp(2, 4);
    final midY = rows ~/ 2;
    var stepUp = true;
    var x = 2;
    while (x + blockW < cols - 2) {
      final y = (stepUp ? midY - amplitude : midY + amplitude)
          .clamp(1, rows - blockH - 1);
      _fillRect(points, x, y, blockW, blockH);
      x += blockW + 2;
      stepUp = !stepUp;
    }
    return points;
  }

  // ─── Level 11: Inward spiral maze of thick block walls ───

  /// Concentric square rings built from solid 2-cell-thick block walls,
  /// each with a wide doorway, so the snake threads inward through the
  /// spiral corridor.
  static Set<GridPoint> _spiral(int cols, int rows) {
    final points = <GridPoint>{};
    const thickness = 2;
    const step = thickness + 3;
    var top = 1;
    var bottom = rows - 2;
    var left = 1;
    var right = cols - 2;
    var ring = 0;
    while (bottom - top > step && right - left > step && ring < 2) {
      final width = right - left + 1;
      // Top and bottom bands (full width).
      _fillRect(points, left, top, width, thickness);
      _fillRect(points, left, bottom - thickness + 1, width, thickness);

      // Left and right bands, leaving a 3-cell door centered vertically.
      final doorY = top + (bottom - top) ~/ 2;
      var y = top + thickness;
      while (y <= bottom - thickness) {
        if ((y - doorY).abs() > 1) {
          _fillRect(points, left, y, thickness, 1);
          _fillRect(points, right - thickness + 1, y, thickness, 1);
        }
        y++;
      }

      top += step;
      bottom -= step;
      left += step;
      right -= step;
      ring++;
    }
    return points;
  }

  // ─── Level 12+: Increasing maze-like obstacles ───

  static Set<GridPoint> _maze(int level, int cols, int rows) {
    final points = <GridPoint>{};

    // Horizontal bar segments – more segments at higher levels.
    final segments = (level - 7).clamp(2, 6);
    final barLen = (cols ~/ 4).clamp(3, cols ~/ 3);

    for (var i = 0; i < segments; i++) {
      final y = ((i + 1) * rows / (segments + 1)).round().clamp(2, rows - 3);
      final xStart = (i.isEven)
          ? (cols ~/ 6)
          : (cols - cols ~/ 6 - barLen);
      for (var x = xStart; x < xStart + barLen && x < cols - 1; x++) {
        points.add(GridPoint(x, y));
      }
    }
    return points;
  }

  /// Verify that no obstacle overlaps the snake starting area.
  static Set<GridPoint> safeObstacles(
    Set<GridPoint> raw,
    List<GridPoint> snake,
    int cols,
    int rows,
  ) {
    // Keep a 2-cell buffer around each snake segment.
    final danger = <GridPoint>{};
    for (final s in snake) {
      for (var dx = -2; dx <= 2; dx++) {
        for (var dy = -2; dy <= 2; dy++) {
          danger.add(GridPoint(s.x + dx, s.y + dy));
        }
      }
    }
    return raw.where((p) =>
      p.x >= 0 && p.x < cols && p.y >= 0 && p.y < rows && !danger.contains(p),
    ).toSet();
  }
}
