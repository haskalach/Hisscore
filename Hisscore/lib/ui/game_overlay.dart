import 'package:flutter/material.dart';

import '../game/high_score_store.dart';
import '../game/snake_engine.dart';
import 'controls.dart';
import 'theme.dart';

// ─── GameOverlay (paused / game-over) ───────────────────

class GameOverlay extends StatelessWidget {
  const GameOverlay({
    super.key,
    required this.phase,
    required this.engine,
    required this.won,
    required this.newHighScore,
    required this.isDailyRun,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.onShare,
    required this.onResume,
    required this.onExitToMenu,
  });

  final GamePhase phase;
  final SnakeEngine engine;
  final bool won;
  final bool newHighScore;
  final bool isDailyRun;
  final int dailyDayNumber;
  final DailyState dailyState;
  final VoidCallback onShare;
  final VoidCallback onResume;
  final VoidCallback onExitToMenu;

  @override
  Widget build(BuildContext context) {
    final isOver = phase == GamePhase.gameOver;
    final title = isOver ? (won ? 'YOU WIN' : 'GAME OVER') : 'PAUSED';

    return ColoredBox(
      color: const Color(0xE603140A),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RetroText.pixel(size: 16, color: RetroColors.amber),
                ),
                if (isOver) ...[
                  const SizedBox(height: 14),
                  Text(
                    engine.score.toString().padLeft(5, '0'),
                    style: RetroText.pixel(
                      size: 18,
                      color: RetroColors.phosphor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ScoreBreakdown(engine: engine),
                  if (isDailyRun) ...[
                    const SizedBox(height: 10),
                    Text(
                      'DAILY #$dailyDayNumber  ·  STREAK ${dailyState.currentStreak}',
                      style: RetroText.pixel(
                        size: 8,
                        color: RetroColors.zenBlue,
                      ),
                    ),
                  ],
                  if (newHighScore) ...[
                    const SizedBox(height: 12),
                    Text(
                      'NEW HISCORE',
                      style: RetroText.pixel(size: 11, color: RetroColors.food),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SecondaryArcadeButton(
                    label: 'SHARE SCORE',
                    color: RetroColors.zenBlue,
                    onPressed: onShare,
                  ),
                ],
                const SizedBox(height: 22),
                ArcadeActionButton(
                  label: isOver ? 'PLAY AGAIN' : 'RESUME',
                  onPressed: onResume,
                ),
                const SizedBox(height: 12),
                SecondaryArcadeButton(
                  label: 'MENU',
                  color: RetroColors.amber,
                  onPressed: onExitToMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Score breakdown on game-over ────────────────────

class ScoreBreakdown extends StatelessWidget {
  const ScoreBreakdown({super.key, required this.engine});

  final SnakeEngine engine;

  @override
  Widget build(BuildContext context) {
    final items = <BreakdownItem>[
      BreakdownItem('APPLES', engine.totalApplesEaten.toString()),
      if (engine.mode == GameMode.adventure)
        BreakdownItem('LEVEL', engine.level.toString()),
      if (engine.bestCombo > 1)
        BreakdownItem(
          'BEST COMBO',
          '×${(1.0 + (engine.bestCombo - 1) * 0.5).toStringAsFixed(1)}',
        ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                items[i].label,
                style: RetroText.pixel(size: 6, color: RetroColors.phosphorDim),
              ),
              const SizedBox(height: 2),
              Text(
                items[i].value,
                style: RetroText.pixel(size: 9, color: RetroColors.phosphor),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class BreakdownItem {
  const BreakdownItem(this.label, this.value);
  final String label;
  final String value;
}

// ─── Lifetime stats (ready screen) ──────────────────

class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.stats});

  final GameStats stats;

  @override
  Widget build(BuildContext context) {
    final comboMult = stats.bestCombo <= 1
        ? 1.0
        : 1.0 + (stats.bestCombo - 1) * 0.5;
    final items = [
      BreakdownItem('GAMES', stats.gamesPlayed.toString()),
      BreakdownItem('APPLES', stats.totalApples.toString()),
      BreakdownItem('BEST COMBO', '×${comboMult.toStringAsFixed(1)}'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                items[i].label,
                style: RetroText.pixel(size: 7, color: RetroColors.metal),
              ),
              const SizedBox(height: 2),
              Text(
                items[i].value,
                style: RetroText.pixel(size: 9, color: RetroColors.phosphorDim),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
