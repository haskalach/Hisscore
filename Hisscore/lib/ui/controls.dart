import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/food_types.dart';
import '../game/snake_engine.dart';
import 'theme.dart';

// ─── Arcade D-pad ───────────────────────────────────

class ArcadeDpad extends StatelessWidget {
  const ArcadeDpad({super.key, required this.onTurn});

  final void Function(Direction direction) onTurn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.2),
          radius: 1.0,
          colors: [Color(0xFF281E16), Color(0xFF16100A), Color(0xFF0C0805)],
          stops: [0.0, 0.65, 1.0],
        ),
        border: Border.all(color: RetroColors.cabinetRim, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: RetroColors.cabinetHighlight.withValues(alpha: 0.25),
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle cross background indentation
          Container(
            width: 36,
            height: 108,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Container(
            width: 108,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
          ),

          // UP Arm
          Positioned(
            top: 5,
            child: _ArcadeDpadArm(
              direction: Direction.up,
              icon: Icons.keyboard_arrow_up,
              label: 'Up',
              width: 34,
              height: 36,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
              onTurn: onTurn,
            ),
          ),

          // DOWN Arm
          Positioned(
            bottom: 5,
            child: _ArcadeDpadArm(
              direction: Direction.down,
              icon: Icons.keyboard_arrow_down,
              label: 'Down',
              width: 34,
              height: 36,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(7),
              ),
              onTurn: onTurn,
            ),
          ),

          // LEFT Arm
          Positioned(
            left: 5,
            child: _ArcadeDpadArm(
              direction: Direction.left,
              icon: Icons.keyboard_arrow_left,
              label: 'Left',
              width: 36,
              height: 34,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(7),
              ),
              onTurn: onTurn,
            ),
          ),

          // RIGHT Arm
          Positioned(
            right: 5,
            child: _ArcadeDpadArm(
              direction: Direction.right,
              icon: Icons.keyboard_arrow_right,
              label: 'Right',
              width: 36,
              height: 34,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(7),
              ),
              onTurn: onTurn,
            ),
          ),

          // Center Pivot Dish
          IgnorePointer(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.25, -0.25),
                  radius: 0.8,
                  colors: [Color(0xFF382A1C), Color(0xFF1E150E)],
                ),
                border: Border.all(
                  color: RetroColors.cabinetRim.withValues(alpha: 0.7),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF120C08),
                    border: Border.all(
                      color: RetroColors.cabinetHighlight.withValues(
                        alpha: 0.35,
                      ),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcadeDpadArm extends StatefulWidget {
  const _ArcadeDpadArm({
    required this.direction,
    required this.icon,
    required this.label,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.onTurn,
  });

  final Direction direction;
  final IconData icon;
  final String label;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final void Function(Direction direction) onTurn;

  @override
  State<_ArcadeDpadArm> createState() => _ArcadeDpadArmState();
}

class _ArcadeDpadArmState extends State<_ArcadeDpadArm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onDown() {
    setState(() => _isPressed = true);
    _press.forward();
    HapticFeedback.lightImpact();
    widget.onTurn(widget.direction);
  }

  void _onUp() {
    setState(() => _isPressed = false);
    _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _onDown(),
        onTapUp: (_) => _onUp(),
        onTapCancel: _onUp,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, _) {
            final p = _press.value;
            final isPressed = _isPressed;
            return Transform.scale(
              scale: 1.0 - p * 0.08,
              child: Container(
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isPressed
                        ? const [Color(0xFF4E3A28), Color(0xFF2C1F14)]
                        : const [Color(0xFF3C2E1F), Color(0xFF241A12)],
                  ),
                  border: Border.all(
                    color: isPressed
                        ? RetroColors.amber
                        : RetroColors.cabinetHighlight.withValues(alpha: 0.6),
                    width: isPressed ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    if (!isPressed)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    if (isPressed)
                      BoxShadow(
                        color: RetroColors.amber.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    color: isPressed
                        ? RetroColors.phosphorHot
                        : RetroColors.amber,
                    size: 28,
                    shadows: [
                      Shadow(
                        color: isPressed
                            ? RetroColors.phosphor.withValues(alpha: 0.8)
                            : RetroColors.amberDim.withValues(alpha: 0.4),
                        blurRadius: isPressed ? 8 : 2,
                      ),
                    ],
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
          style: RetroText.pixel(size: 7, color: RetroColors.phosphorDim),
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
          style: RetroText.pixel(size: 6, color: RetroColors.metal),
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

  @override
  Widget build(BuildContext context) {
    final accent = mode.accentColor;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? accent : accent.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: Text(
          mode.label,
          style: RetroText.pixel(
            size: 6,
            color: isSelected ? RetroColors.cabinet : accent,
          ),
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
                style: RetroText.pixel(size: 5, color: RetroColors.metal),
              ),
            ],
          ),
      ],
    );
  }
}
