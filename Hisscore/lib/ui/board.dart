import 'dart:math' show cos, pi, sin;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/food_types.dart';
import '../game/snake_engine.dart';
import 'particles.dart';
import 'theme.dart';

class SnakeBoard extends StatefulWidget {
  const SnakeBoard({
    super.key,
    required this.engine,
    required this.pulse,
    this.tickProgress = 1.0,
    this.particles,
    this.onSwipe,
    this.fullBleed = false,
  });

  final SnakeEngine engine;
  final double pulse;

  /// Fill the whole box with no bezel — how the board is shown during
  /// play. The framed, aspect-locked version is used for the intro
  /// screen's demo.
  final bool fullBleed;

  /// How far the current tick has played out, 0..1. Drives the
  /// cell-to-cell movement animation.
  final double tickProgress;

  final ParticleSystem? particles;
  final void Function(Direction direction)? onSwipe;

  @override
  State<SnakeBoard> createState() => _SnakeBoardState();
}

class _SnakeBoardState extends State<SnakeBoard> {
  /// How far a finger must travel before it counts as a swipe.
  static const double _swipeThreshold = 16;

  Offset? _dragOrigin;

  /// Grid, scanlines and vignette never change between frames, so they
  /// are rasterized once per size instead of ~160 draw calls every
  /// frame. Held here because painters are rebuilt on every paint.
  final BoardLayerCache _staticLayers = BoardLayerCache();

  @override
  void dispose() {
    _staticLayers.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final origin = _dragOrigin;
    if (origin == null) return;
    final delta = details.localPosition - origin;
    if (delta.distance < _swipeThreshold) return;

    final direction = delta.dx.abs() > delta.dy.abs()
        ? (delta.dx > 0 ? Direction.right : Direction.left)
        : (delta.dy > 0 ? Direction.down : Direction.up);
    widget.onSwipe?.call(direction);

    // Re-anchor so one continuous gesture can chain several turns.
    _dragOrigin = details.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _dragOrigin = details.localPosition,
      onPanStart: (details) => _dragOrigin = details.localPosition,
      onPanUpdate: _onDragUpdate,
      onPanEnd: (_) => _dragOrigin = null,
      onPanCancel: () => _dragOrigin = null,
      child: widget.fullBleed ? _buildScreen() : _buildFramedScreen(),
    );
  }

  Widget _buildScreen() {
    return ClipRect(
      child: CustomPaint(
        painter: SnakeBoardPainter(
          engine: widget.engine,
          pulse: widget.pulse,
          tickProgress: widget.tickProgress,
          particles: widget.particles,
          staticLayers: _staticLayers,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _buildFramedScreen() {
    return AspectRatio(
      aspectRatio: widget.engine.columns / widget.engine.rows,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RetroColors.screen,
          border: Border.all(color: RetroColors.phosphorDim, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x6600FF66),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: _buildScreen(),
      ),
    );
  }
}

/// Caches the board's unchanging layers (grid, scanlines, vignette) as a
/// recorded picture, rebuilt only when the canvas size changes.
class BoardLayerCache {
  final _CachedPicture _backdrop = _CachedPicture();
  final _CachedPicture _overlay = _CachedPicture();

  ui.Picture pictureFor(Size size, void Function(Canvas) draw) =>
      _backdrop.forSize(size, draw);

  ui.Picture overlayFor(Size size, void Function(Canvas) draw) =>
      _overlay.forSize(size, draw);

  void dispose() {
    _backdrop.dispose();
    _overlay.dispose();
  }
}

class _CachedPicture {
  ui.Picture? _picture;
  Size? _size;

  ui.Picture forSize(Size size, void Function(Canvas) draw) {
    final cached = _picture;
    if (cached != null && _size == size) {
      return cached;
    }
    cached?.dispose();
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder));
    final picture = recorder.endRecording();
    _picture = picture;
    _size = size;
    return picture;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _size = null;
  }
}

class SnakeBoardPainter extends CustomPainter {
  SnakeBoardPainter({
    required this.engine,
    required this.pulse,
    this.tickProgress = 1.0,
    this.particles,
    this.staticLayers,
  });

  final SnakeEngine engine;
  final double pulse;
  final double tickProgress;
  final ParticleSystem? particles;
  final BoardLayerCache? staticLayers;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / engine.columns;
    final cellH = size.height / engine.rows;

    // ── Background + grid (cached) ──
    final cache = staticLayers;
    if (cache != null) {
      canvas.drawPicture(
        cache.pictureFor(size, (c) => _paintBackdrop(c, size, cellW, cellH)),
      );
    } else {
      _paintBackdrop(canvas, size, cellW, cellH);
    }

    // ── Obstacles ──
    if (engine.obstacles.isNotEmpty) {
      for (final obs in engine.obstacles) {
        final rect = _cell(obs, cellW, cellH).deflate(cellW * 0.04);
        final obsPaint = Paint()..color = RetroColors.obstacle;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(cellW * 0.1)),
          obsPaint,
        );
        // Highlight edge
        final rimPaint = Paint()
          ..color = RetroColors.obstacleRim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(cellW * 0.1)),
          rimPaint,
        );
      }
    }

    // ── Snake glow pass ──
    for (var i = engine.snake.length - 1; i >= 0; i--) {
      final rect = _segmentRect(i, cellW, cellH).inflate(cellW * 0.12);
      final t = engine.snake.length > 1 ? i / (engine.snake.length - 1) : 0.0;
      final glowColor = Color.lerp(
        RetroColors.phosphorHot,
        RetroColors.snakeTail,
        t,
      )!;
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellW * 0.25)),
        glowPaint,
      );
    }

    // ── Snake body (gradient head → tail) ──
    for (var i = engine.snake.length - 1; i >= 0; i--) {
      final isHead = i == 0;
      final t = engine.snake.length > 1 ? i / (engine.snake.length - 1) : 0.0;
      // Taper toward the tail so the body reads as a snake rather than
      // a chain of identical blocks.
      final rect = _segmentRect(
        i,
        cellW,
        cellH,
      ).deflate(cellW * (0.08 + 0.14 * t));

      final bodyColor = isHead
          ? RetroColors.phosphorHot
          : Color.lerp(RetroColors.phosphor, RetroColors.snakeTail, t)!;

      final bodyPaint = Paint()..color = bodyColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellW * 0.18)),
        bodyPaint,
      );

      // ── Connecting segments (fill gaps between adjacent segments) ──
      if (i < engine.snake.length - 1) {
        final here = rect.center;
        final behind = _segmentRect(i + 1, cellW, cellH).center;
        final dx = behind.dx - here.dx;
        final dy = behind.dy - here.dy;
        // Only draw a connector between neighbours — skip the long jump
        // a wrapped segment makes across the board.
        if (dx.abs() <= cellW * 1.5 &&
            dy.abs() <= cellH * 1.5 &&
            (dx != 0 || dy != 0)) {
          // Connectors taper with the body they join.
          final taper = 1.0 - 0.28 * t;
          final connRect = Rect.fromCenter(
            center: Offset(
              (here.dx + behind.dx) / 2,
              (here.dy + behind.dy) / 2,
            ),
            width: (dx != 0 ? cellW * 0.6 : cellW * 0.65) * taper,
            height: (dy != 0 ? cellH * 0.6 : cellH * 0.65) * taper,
          );
          final connColor = Color.lerp(
            RetroColors.phosphor,
            RetroColors.snakeTail,
            t,
          )!;
          canvas.drawRRect(
            RRect.fromRectAndRadius(connRect, Radius.circular(cellW * 0.15)),
            Paint()..color = connColor,
          );
        }
      }

      if (isHead) {
        _drawEyes(canvas, rect, cellW);
        // Shield indicator on head — breathes so it reads as active.
        if (engine.hasShield) {
          final shieldPaint = Paint()
            ..color = RetroColors.shieldCyan.withValues(
              alpha: 0.25 + pulse * 0.45,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.inflate(cellW * (0.08 + pulse * 0.06)),
              Radius.circular(cellW * 0.22),
            ),
            shieldPaint,
          );
        }
      }
    }

    // ── Food items ──
    for (final item in engine.foods) {
      _paintFood(canvas, item, cellW, cellH);
    }

    // ── Particles ──
    particles?.update();
    particles?.paint(canvas);

    // ── CRT overlay: scanlines + vignette (cached) ──
    if (cache != null) {
      canvas.drawPicture(
        cache.overlayFor(size, (c) => _paintCrtOverlay(c, size)),
      );
    } else {
      _paintCrtOverlay(canvas, size);
    }
  }

  /// Screen fill and grid — identical every frame for a given size.
  void _paintBackdrop(Canvas canvas, Size size, double cellW, double cellH) {
    canvas.drawRect(Offset.zero & size, Paint()..color = RetroColors.screen);

    final gridPaint = Paint()
      ..color = RetroColors.grid
      ..strokeWidth = 0.8;
    for (var x = 1; x < engine.columns; x++) {
      final dx = x * cellW;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (var y = 1; y < engine.rows; y++) {
      final dy = y * cellH;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }
  }

  /// Scanlines and vignette — also fixed for a given size.
  void _paintCrtOverlay(Canvas canvas, Size size) {
    final scan = Paint()..color = RetroColors.scanline;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.2), scan);
    }

    final vignetteRect = Offset.zero & size;
    final vignettePaint = Paint()
      ..shader = ui.Gradient.radial(
        vignetteRect.center,
        size.longestSide * 0.7,
        [const Color(0x00000000), const Color(0x80000000)],
        [0.55, 1.0],
      );
    canvas.drawRect(vignetteRect, vignettePaint);
  }

  // ─── Food rendering per type ──────────────────────

  /// How long a pickup takes to scale up after spawning.
  static const double _spawnPopMs = 180;

  void _paintFood(Canvas canvas, FoodItem item, double cellW, double cellH) {
    final rect = _cell(item.position, cellW, cellH);
    final center = rect.center;
    final r = rect.shortestSide / 2;

    // Pulsing animation factor (only for permanent foods).
    var foodScale = item.lifetimeMs == null
        ? 0.72 + (pulse * 0.14)
        : 0.60 + (item.lifeFraction(engine.elapsedMs) * 0.26);

    // Pop in over the first moments on screen, so pickups arrive
    // instead of just appearing.
    final age = item.ageMs(engine.elapsedMs);
    if (age < _spawnPopMs) {
      final t = (age / _spawnPopMs).clamp(0.0, 1.0);
      // Overshoot slightly, then settle.
      foodScale *= 0.4 + 0.75 * t - 0.15 * t * t;
    }

    switch (item.type) {
      case FoodType.apple:
        // Red apple with stem.
        final applePaint = Paint()..color = RetroColors.food;
        canvas.drawCircle(center, r * foodScale, applePaint);
        canvas.drawCircle(
          center.translate(0, -rect.height * 0.22),
          r * 0.12,
          Paint()..color = RetroColors.phosphorDim,
        );

      case FoodType.star:
        // Gold star shape (5-pointed).
        _drawStar(canvas, center, r * foodScale * 0.9, RetroColors.starGold);
        // Glow.
        canvas.drawCircle(
          center,
          r * foodScale,
          Paint()
            ..color = RetroColors.starGold.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );

      case FoodType.shield:
        // Cyan diamond.
        final shieldPaint = Paint()..color = RetroColors.shieldCyan;
        final path = Path()
          ..moveTo(center.dx, center.dy - r * foodScale)
          ..lineTo(center.dx + r * foodScale * 0.7, center.dy)
          ..lineTo(center.dx, center.dy + r * foodScale)
          ..lineTo(center.dx - r * foodScale * 0.7, center.dy)
          ..close();
        canvas.drawPath(path, shieldPaint);

      case FoodType.speedBurst:
        // Yellow lightning bolt (classic zigzag polygon).
        final boltPaint = Paint()..color = RetroColors.speedYellow;
        final s = r * foodScale;
        final path = Path()
          ..moveTo(center.dx + s * 0.15, center.dy - s)
          ..lineTo(center.dx - s * 0.35, center.dy + s * 0.1)
          ..lineTo(center.dx + s * 0.05, center.dy + s * 0.1)
          ..lineTo(center.dx - s * 0.15, center.dy + s)
          ..lineTo(center.dx + s * 0.35, center.dy - s * 0.1)
          ..lineTo(center.dx - s * 0.05, center.dy - s * 0.1)
          ..close();
        canvas.drawPath(path, boltPaint);

      case FoodType.shrink:
        // Purple ring.
        final shrinkPaint = Paint()
          ..color = RetroColors.shrinkPurple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(center, r * foodScale * 0.7, shrinkPaint);
        canvas.drawCircle(
          center,
          r * foodScale * 0.3,
          Paint()..color = RetroColors.shrinkPurple,
        );

      case FoodType.magnet:
        // Pink horseshoe magnet.
        final s = r * foodScale;
        final magnetPaint = Paint()
          ..color = RetroColors.magnetPink
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.32
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(center.dx - s * 0.55, center.dy - s * 0.6)
          ..lineTo(center.dx - s * 0.55, center.dy + s * 0.15)
          ..arcToPoint(
            Offset(center.dx + s * 0.55, center.dy + s * 0.15),
            radius: Radius.circular(s * 0.55),
          )
          ..lineTo(center.dx + s * 0.55, center.dy - s * 0.6);
        canvas.drawPath(path, magnetPaint);
        // Pole tips.
        final tipPaint = Paint()..color = RetroColors.phosphorHot;
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx - s * 0.55, center.dy - s * 0.72),
            width: s * 0.34,
            height: s * 0.26,
          ),
          tipPaint,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx + s * 0.55, center.dy - s * 0.72),
            width: s * 0.34,
            height: s * 0.26,
          ),
          tipPaint,
        );
    }

    // Timed food: blink when about to expire.
    if (item.lifetimeMs != null) {
      final frac = item.lifeFraction(engine.elapsedMs);
      if (frac < 0.3 && pulse > 0.5) {
        // Flash overlay to signal imminent despawn.
        canvas.drawCircle(
          center,
          r * 0.5,
          Paint()..color = const Color(0x44FFFFFF),
        );
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = (i * pi / points) - pi / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawEyes(Canvas canvas, Rect head, double cellW) {
    final eye = Paint()..color = RetroColors.screen;
    final offset = switch (engine.direction) {
      Direction.right => const Offset(0.22, 0),
      Direction.left => const Offset(-0.22, 0),
      Direction.up => const Offset(0, -0.22),
      Direction.down => const Offset(0, 0.22),
    };
    final cx = head.center.dx + head.width * offset.dx;
    final cy = head.center.dy + head.height * offset.dy;
    final r = cellW * 0.08;
    // Eye whites (slightly bigger).
    final pupilOffset = switch (engine.direction) {
      Direction.right || Direction.left => Offset(0, r * 1.6),
      Direction.up || Direction.down => Offset(r * 1.6, 0),
    };
    canvas.drawCircle(Offset(cx - pupilOffset.dx, cy - pupilOffset.dy), r, eye);
    canvas.drawCircle(Offset(cx + pupilOffset.dx, cy + pupilOffset.dy), r, eye);
  }

  Rect _cell(GridPoint point, double cellW, double cellH) {
    return Rect.fromLTWH(point.x * cellW, point.y * cellH, cellW, cellH);
  }

  /// Where segment [i] sits right now, part-way through the current tick.
  ///
  /// Each segment slides from where it was to where it is, which is the
  /// position of the segment that was ahead of it — so the whole snake
  /// flows forward instead of jumping a cell at a time.
  Rect _segmentRect(int i, double cellW, double cellH) {
    final current = engine.snake[i];
    final previous = engine.previousSnake;

    // A segment added this tick (the snake grew) has nowhere to come
    // from — it grows out of the old tail, which means it stays put.
    final from = i < previous.length
        ? previous[i]
        : (previous.isNotEmpty ? previous.last : current);

    final dx = (current.x - from.x).toDouble();
    final dy = (current.y - from.y).toDouble();

    // A wrapped segment teleports across the board; sliding it would
    // sweep the whole width. Snap instead.
    if (dx.abs() > 1 || dy.abs() > 1) {
      return _cell(current, cellW, cellH);
    }

    final t = tickProgress.clamp(0.0, 1.0);
    return Rect.fromLTWH(
      (from.x + dx * t) * cellW,
      (from.y + dy * t) * cellH,
      cellW,
      cellH,
    );
  }

  @override
  bool shouldRepaint(covariant SnakeBoardPainter oldDelegate) => true;
}

// ─── Board sizing ───────────────────────────────────

/// A grid that fills [size] with square-ish cells: 20 across in
/// portrait with as many rows as the screen is tall, flipped for
/// landscape. Clamped so an extreme window can't produce an absurd
/// board.
({int columns, int rows}) boardGridFor(Size size) {
  const base = 20;
  const maxSpan = 46;
  if (size.width <= 0 || size.height <= 0) {
    return (columns: base, rows: base);
  }
  if (size.height >= size.width) {
    final rows = (base * size.height / size.width).round().clamp(base, maxSpan);
    return (columns: base, rows: rows);
  }
  final columns = (base * size.width / size.height).round().clamp(
    base,
    maxSpan,
  );
  return (columns: columns, rows: base);
}
