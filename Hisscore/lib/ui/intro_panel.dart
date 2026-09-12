import 'package:flutter/material.dart';

import '../game/high_score_store.dart';
import '../game/snake_engine.dart';
import 'ready_tabs.dart';
import 'theme.dart';

// ─── Intro panel (over the attract demo) ────────────

class IntroPanel extends StatelessWidget {
  const IntroPanel({
    super.key,
    required this.blinkOn,
    required this.selectedMode,
    required this.onModeChanged,
    required this.readyTab,
    required this.onReadyTabChanged,
    required this.stats,
    required this.topScores,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.playedDailyToday,
    required this.onStartDaily,
  });

  final bool blinkOn;
  final GameMode selectedMode;
  final ValueChanged<GameMode> onModeChanged;
  final ReadyTab readyTab;
  final ValueChanged<ReadyTab> onReadyTabChanged;
  final GameStats stats;
  final List<ScoreEntry> topScores;
  final int dailyDayNumber;
  final DailyState dailyState;
  final bool playedDailyToday;
  final VoidCallback onStartDaily;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Dark enough to read against, sheer enough to keep the demo
      // visible behind it.
      color: const Color(0xCC03140A),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: blinkOn ? 1 : 0.35,
                child: Text(
                  'PRESS START',
                  textAlign: TextAlign.center,
                  style: RetroText.pixel(size: 14, color: RetroColors.amber),
                ),
              ),
              const SizedBox(height: 14),
              ReadyTabBar(selected: readyTab, onChanged: onReadyTabChanged),
              const SizedBox(height: 14),
              switch (readyTab) {
                ReadyTab.modes => ReadyModesTab(
                  selectedMode: selectedMode,
                  onModeChanged: onModeChanged,
                  dailyDayNumber: dailyDayNumber,
                  dailyState: dailyState,
                  playedDailyToday: playedDailyToday,
                  onStartDaily: onStartDaily,
                ),
                ReadyTab.how => const ReadyHowTab(),
                ReadyTab.stats => ReadyStatsTab(
                  stats: stats,
                  topScores: topScores,
                  dailyState: dailyState,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}
