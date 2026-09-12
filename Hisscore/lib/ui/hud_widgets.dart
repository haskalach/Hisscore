import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// ─── Mini stat chip (level, combo, shield) ──────────

class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    this.color = RetroColors.phosphor,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: RetroText.pixel(size: 6, color: RetroColors.phosphorDim),
          ),
        if (label.isNotEmpty) const SizedBox(height: 2),
        Text(value, style: RetroText.pixel(size: 11, color: color)),
      ],
    );
  }
}

// ─── Pause button (in-game HUD) ─────────────────────

/// Deliberately a small dedicated target rather than tap-anywhere: the
/// whole board is a swipe surface, so a stray tap must never pause.
class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pause',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: RetroColors.screen.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RetroColors.phosphorDim, width: 1.4),
          ),
          child: const Icon(Icons.pause, size: 20, color: RetroColors.phosphor),
        ),
      ),
    );
  }
}
