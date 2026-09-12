import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/food_types.dart';
import '../game/snake_engine.dart';
import 'theme.dart';

// ─── Arcade action button (PLAY / PAUSE / etc.) ─────

class ArcadeActionButton extends StatefulWidget {
  const ArcadeActionButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<ArcadeActionButton> createState() => _ArcadeActionButtonState();
}

class _ArcadeActionButtonState extends State<ArcadeActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
    );
  }

  @override
  void dispose() {
    _glow.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_glow, _press]),
      builder: (context, child) {
        final scale = 1.0 - _press.value * 0.08;
        return Semantics(
          button: true,
          label: widget.label,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                _press.forward();
                HapticFeedback.mediumImpact();
                widget.onPressed();
              },
              onTapUp: (_) => _press.reverse(),
              onTapCancel: () => _press.reverse(),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5A4432), Color(0xFF281C12)],
                    ),
                    border: Border.all(
                      color: RetroColors.cabinetHighlight.withValues(
                        alpha: 0.5,
                      ),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: RetroColors.cherry.withValues(
                          alpha: 0.25 + _glow.value * 0.25,
                        ),
                        blurRadius: 10 + _glow.value * 6,
                        spreadRadius: _glow.value * 1.5,
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFF5252),
                          RetroColors.cherry,
                          Color(0xFFB71C1C),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      widget.label,
                      style: RetroText.pixel(size: 9.5, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Secondary arcade button (MENU / CHANGE MODE / RESUME) ────

class SecondaryArcadeButton extends StatelessWidget {
  const SecondaryArcadeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = RetroColors.metal,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: RetroColors.screen,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: 0.7),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(label, style: RetroText.pixel(size: 7.5, color: color)),
          ),
        ),
      ),
    );
  }
}

// ─── Score readout ───────────────────────────────────

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
          style: RetroText.pixel(size: 7, color: RetroColors.phosphorDim),
        ),
        const SizedBox(height: 4),
        Text(
          padded,
          key: Key('score-$label'),
          style: RetroText.pixel(
            size: 13,
            color: highlight ? RetroColors.amber : RetroColors.phosphor,
          ),
        ),
      ],
    );
  }
}

// ─── Game mode selector ─────────────────────────────

class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final GameMode selected;
  final ValueChanged<GameMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SELECT MODE',
          style: RetroText.pixel(size: 9, color: RetroColors.phosphorDim),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final mode in GameMode.values)
              _ModeChip(
                mode: mode,
                isSelected: mode == selected,
                onTap: () => onChanged(mode),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          selected.description,
          style: RetroText.pixel(size: 8, color: RetroColors.metal),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final GameMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  static const _chipFade = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final accent = mode.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _chipFade,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? accent : accent.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        // The label fades with the fill — switching it instantly leaves
        // dark text on a still-dark chip for the length of the fade.
        child: AnimatedDefaultTextStyle(
          duration: _chipFade,
          style: RetroText.pixel(
            size: 7,
            color: isSelected ? RetroColors.cabinet : accent,
          ),
          child: Text(mode.label),
        ),
      ),
    );
  }
}

// ─── Food legend (ready screen) ─────────────────────

/// Small key showing what each collectible on the board does, so a
/// first-time player isn't guessing what the colored shapes mean.
class FoodLegend extends StatelessWidget {
  const FoodLegend({super.key});

  static const _entries = [
    (FoodType.apple, RetroColors.food),
    (FoodType.star, RetroColors.starGold),
    (FoodType.shield, RetroColors.shieldCyan),
    (FoodType.speedBurst, RetroColors.speedYellow),
    (FoodType.shrink, RetroColors.shrinkPurple),
    (FoodType.magnet, RetroColors.magnetPink),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final (type, color) in _entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                type.label,
                style: RetroText.pixel(size: 7, color: RetroColors.metal),
              ),
            ],
          ),
      ],
    );
  }
}
