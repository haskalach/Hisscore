import 'package:flutter/material.dart';

import '../game/snake_engine.dart';
import 'theme.dart';

class ArcadeDpad extends StatelessWidget {
  const ArcadeDpad({super.key, required this.onTurn});

  final void Function(Direction direction) onTurn;

  @override
  Widget build(BuildContext context) {
    Widget button(Direction direction, IconData icon, String label) {
      return Semantics(
        button: true,
        label: label,
        child: Material(
          color: RetroColors.cabinetRim,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onTurn(direction),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: RetroColors.amber, size: 28),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Direction.up, Icons.keyboard_arrow_up, 'Up'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            button(Direction.left, Icons.keyboard_arrow_left, 'Left'),
            const SizedBox(width: 56),
            button(Direction.right, Icons.keyboard_arrow_right, 'Right'),
          ],
        ),
        const SizedBox(height: 8),
        button(Direction.down, Icons.keyboard_arrow_down, 'Down'),
      ],
    );
  }
}

class ArcadeActionButton extends StatelessWidget {
  const ArcadeActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: RetroColors.cherry,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: Text(
              label,
              style: RetroText.pixel(size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class ScoreReadout extends StatelessWidget {
  const ScoreReadout({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int value;
  final bool highlight;

  String get padded => value.toString().padLeft(5, '0');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: RetroText.pixel(size: 8, color: RetroColors.phosphorDim),
        ),
        const SizedBox(height: 6),
        Text(
          padded,
          key: Key('score-$label'),
          style: RetroText.pixel(
            size: 14,
            color: highlight ? RetroColors.amber : RetroColors.phosphor,
          ),
        ),
      ],
    );
  }
}
