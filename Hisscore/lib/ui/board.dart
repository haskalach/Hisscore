import 'dart:math' show cos, pi, sin;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/food_types.dart';
import '../game/snake_engine.dart';
import 'particles.dart';
import 'theme.dart';

class SnakeBoard extends StatelessWidget {
  const SnakeBoard({
    super.key,
    required this.engine,
    required this.pulse,
    this.particles,
    this.onSwipe,
  });

  final SnakeEngine engine;
  final double pulse;
  final ParticleSystem? particles;
  final void Function(Direction direction)? onSwipe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanEnd: (details) {
        final velocity = details.velocity.pixelsPerSecond;
        if (velocity.distance < 180) {
          return;
        }
        final direction = velocity.dx.abs() > velocity.dy.abs()
            ? (velocity.dx > 0 ? Direction.right : Direction.left)
            : (velocity.dy > 0 ? Direction.down : Direction.up);
        onSwipe?.call(direction);
      },
      child: AspectRatio(
        aspectRatio: engine.columns / engine.rows,
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
          child: ClipRect(
            child: CustomPaint(
              painter: SnakeBoardPainter(
                engine: engine,
                pulse: pulse,
                particles: particles,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class SnakeBoardPainter extends CustomPainter {
  SnakeBoardPainter({
    required this.engine,
    required this.pulse,
    this.particles,
  });

  final SnakeEngine engine;
  final double pulse;
  final ParticleSystem? particles;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / engine.columns;
    final cellH = size.height / engine.rows;

    // ── Background ──
    final bg = Paint()..color = RetroColors.screen;
    canvas.drawRect(Offset.zero & size, bg);

    // ── Grid lines ──
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
      final segment = engine.snake[i];
      final rect = _cell(segment, cellW, cellH).inflate(cellW * 0.12);
      final t = engine.snake.length > 1
          ? i / (engine.snake.length - 1)
          : 0.0;
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
      final segment = engine.snake[i];
      final rect = _cell(segment, cellW, cellH).deflate(cellW * 0.08);
      final isHead = i == 0;
      final t = engine.snake.length > 1
          ? i / (engine.snake.length - 1)
          : 0.0;

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
        final prev = engine.snake[i + 1];
        final dx = segment.x - prev.x;
        final dy = segment.y - prev.y;
        // Only draw connector if segments are adjacent (not wrapping).
        if (dx.abs() <= 1 && dy.abs() <= 1 && (dx != 0 || dy != 0)) {
          final connRect = Rect.fromCenter(
            center: Offset(
              (segment.x + prev.x) / 2 * cellW + cellW / 2,
              (segment.y + prev.y) / 2 * cellH + cellH / 2,
            ),
            width: dx != 0 ? cellW * 0.6 : cellW * 0.65,
            height: dy != 0 ? cellH * 0.6 : cellH * 0.65,
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
        // Shield indicator on head.
        if (engine.hasShield) {
          final shieldPaint = Paint()
            ..color = RetroColors.shieldCyan.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.inflate(cellW * 0.1),
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

    // ── Scanlines ──
    final scan = Paint()..color = RetroColors.scanline;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.2), scan);
    }

    // ── Vignette ──
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

  void _paintFood(Canvas canvas, FoodItem item, double cellW, double cellH) {
    final rect = _cell(item.position, cellW, cellH);
    final center = rect.center;
    final r = rect.shortestSide / 2;

    // Pulsing animation factor (only for permanent foods).
    final foodScale = item.lifetime == null
        ? 0.72 + (pulse * 0.14)
        : 0.60 + (item.lifeFraction(engine.totalTicks) * 0.26);

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
    if (item.lifetime != null) {
      final frac = item.lifeFraction(engine.totalTicks);
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

  @override
  bool shouldRepaint(covariant SnakeBoardPainter oldDelegate) => true;
}
