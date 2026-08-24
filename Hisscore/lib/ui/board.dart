import 'package:flutter/material.dart';

import '../game/snake_engine.dart';
import 'theme.dart';

class SnakeBoard extends StatelessWidget {
  const SnakeBoard({
    super.key,
    required this.engine,
    required this.pulse,
    this.onSwipe,
  });

  final SnakeEngine engine;
  final double pulse;
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
          child: CustomPaint(
            painter: SnakeBoardPainter(engine: engine, pulse: pulse),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class SnakeBoardPainter extends CustomPainter {
  SnakeBoardPainter({required this.engine, required this.pulse});

  final SnakeEngine engine;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / engine.columns;
    final cellH = size.height / engine.rows;

    final bg = Paint()..color = RetroColors.screen;
    canvas.drawRect(Offset.zero & size, bg);

    final gridPaint = Paint()
      ..color = RetroColors.grid
      ..strokeWidth = 1;
    for (var x = 1; x < engine.columns; x++) {
      final dx = x * cellW;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (var y = 1; y < engine.rows; y++) {
      final dy = y * cellH;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    for (var i = engine.snake.length - 1; i >= 0; i--) {
      final segment = engine.snake[i];
      final rect = _cell(segment, cellW, cellH).deflate(cellW * 0.08);
      final isHead = i == 0;
      final bodyPaint = Paint()
        ..color = isHead ? RetroColors.phosphorHot : RetroColors.phosphor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellW * 0.18)),
        bodyPaint,
      );
      if (isHead) {
        _drawEyes(canvas, rect, cellW);
      }
    }

    final foodRect = _cell(engine.food, cellW, cellH);
    final foodScale = 0.72 + (pulse * 0.14);
    final foodPaint = Paint()..color = RetroColors.food;
    canvas.drawCircle(foodRect.center, foodRect.shortestSide * foodScale / 2, foodPaint);
    canvas.drawCircle(
      foodRect.center.translate(0, -foodRect.height * 0.22),
      foodRect.shortestSide * 0.08,
      Paint()..color = RetroColors.phosphorDim,
    );

    final scan = Paint()..color = const Color(0x22000000);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.2), scan);
    }
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
    canvas.drawCircle(Offset(cx, cy - r * 1.6), r, eye);
    canvas.drawCircle(Offset(cx, cy + r * 1.6), r, eye);
  }

  Rect _cell(GridPoint point, double cellW, double cellH) {
    return Rect.fromLTWH(point.x * cellW, point.y * cellH, cellW, cellH);
  }

  @override
  bool shouldRepaint(covariant SnakeBoardPainter oldDelegate) => true;
}
