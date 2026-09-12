import 'package:flutter/material.dart';

import 'theme.dart';

// ─── Floating popup text (score gains, combos, level-ups) ──

class FloatingLabel {
  FloatingLabel({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    this.big = false,
  });

  final int id;
  final String text;
  final double x;
  final double y;
  final Color color;
  final bool big;
}

class FloatingLabelView extends StatelessWidget {
  const FloatingLabelView({super.key, required this.label});

  final FloatingLabel label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: label.x - 60,
      top: label.y - 20,
      width: 120,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, t, _) {
            return Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -24 * t),
                child: Transform.scale(
                  scale: 0.8 + (t < 0.25 ? t * 4 * 0.3 : 0.3),
                  child: Center(
                    child: Text(
                      label.text,
                      textAlign: TextAlign.center,
                      style: RetroText.pixel(
                        size: label.big ? 10 : 7,
                        color: label.color,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
