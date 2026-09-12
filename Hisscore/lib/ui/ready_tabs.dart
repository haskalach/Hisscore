import 'package:flutter/material.dart';

import '../game/high_score_store.dart';
import '../game/snake_engine.dart';
import 'controls.dart';
import 'game_overlay.dart';
import 'theme.dart';

// ─── Ready screen tabs ──────────────────────────────

/// The ready screen used to stack modes, legend, stats and scores in one
/// column, which left everything at 5–6px on a phone. One tab at a time
/// buys the room to set type at a readable size.
enum ReadyTab {
  modes('MODES'),
  how('HOW'),
  stats('STATS');

  const ReadyTab(this.label);
  final String label;
}

class ReadyTabBar extends StatelessWidget {
  const ReadyTabBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _tabFade = Duration(milliseconds: 200);

  final ReadyTab selected;
  final ValueChanged<ReadyTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final tab in ReadyTab.values) ...[
          if (tab != ReadyTab.values.first) const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onChanged(tab),
            child: AnimatedContainer(
              duration: _tabFade,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tab == selected
                    ? RetroColors.phosphor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: tab == selected
                      ? RetroColors.phosphor
                      : RetroColors.phosphorDim,
                  width: 1.5,
                ),
              ),
              // The label fades with the fill. Switching it instantly
              // would leave dark text on a still-dark chip for the
              // length of the fade.
              child: AnimatedDefaultTextStyle(
                duration: _tabFade,
                style: RetroText.pixel(
                  size: 8,
                  color: tab == selected
                      ? RetroColors.cabinet
                      : RetroColors.phosphorDim,
                ),
                child: Text(tab.label),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ReadyModesTab extends StatelessWidget {
  const ReadyModesTab({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.playedDailyToday,
    required this.onStartDaily,
  });

  final GameMode selectedMode;
  final ValueChanged<GameMode> onModeChanged;
  final int dailyDayNumber;
  final DailyState dailyState;
  final bool playedDailyToday;
  final VoidCallback onStartDaily;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ModeSelector(selected: selectedMode, onChanged: onModeChanged),
        const SizedBox(height: 18),
        DailyChallengeCard(
          dayNumber: dailyDayNumber,
          dailyState: dailyState,
          playedToday: playedDailyToday,
          onStart: onStartDaily,
        ),
      ],
    );
  }
}

class ReadyHowTab extends StatelessWidget {
  const ReadyHowTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PICKUPS',
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 10),
        const FoodLegend(),
        const SizedBox(height: 18),
        Text(
          'CONTROLS',
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 10),
        for (final line in const [
          'SWIPE OR DRAG TO TURN',
          'ARROWS / WASD',
          'SPACE: PAUSE  ·  M: MENU',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: RetroText.pixel(size: 7, color: RetroColors.metal),
            ),
          ),
      ],
    );
  }
}

class ReadyStatsTab extends StatelessWidget {
  const ReadyStatsTab({
    super.key,
    required this.stats,
    required this.topScores,
    required this.dailyState,
  });

  final GameStats stats;
  final List<ScoreEntry> topScores;
  final DailyState dailyState;

  @override
  Widget build(BuildContext context) {
    if (stats.gamesPlayed == 0 && topScores.isEmpty) {
      return Text(
        'NO RUNS YET',
        style: RetroText.pixel(size: 8, color: RetroColors.metal),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stats.gamesPlayed > 0) ...[
          StatsRow(stats: stats),
          const SizedBox(height: 16),
        ],
        if (dailyState.bestStreak > 0) ...[
          Text(
            'BEST STREAK ${dailyState.bestStreak} DAY'
            '${dailyState.bestStreak == 1 ? '' : 'S'}',
            style: RetroText.pixel(size: 7, color: RetroColors.zenBlue),
          ),
          const SizedBox(height: 16),
        ],
        if (topScores.isNotEmpty) TopScoresList(scores: topScores),
      ],
    );
  }
}

// ─── Daily challenge card (ready screen) ─────────────

class DailyChallengeCard extends StatelessWidget {
  const DailyChallengeCard({
    super.key,
    required this.dayNumber,
    required this.dailyState,
    required this.playedToday,
    required this.onStart,
  });

  final int dayNumber;
  final DailyState dailyState;
  final bool playedToday;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RetroColors.zenBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: RetroColors.zenBlue.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DAILY CHALLENGE #$dayNumber',
            style: RetroText.pixel(size: 8, color: RetroColors.zenBlue),
          ),
          if (dailyState.currentStreak > 0) ...[
            const SizedBox(height: 6),
            Text(
              'STREAK ${dailyState.currentStreak} DAY'
              '${dailyState.currentStreak == 1 ? '' : 'S'}'
              '${dailyState.bestStreak > dailyState.currentStreak ? '  ·  BEST ${dailyState.bestStreak}' : ''}',
              style: RetroText.pixel(size: 7, color: RetroColors.metal),
            ),
          ],
          if (playedToday) ...[
            const SizedBox(height: 4),
            Text(
              "TODAY'S SCORE ${dailyState.lastScore}",
              style: RetroText.pixel(size: 7, color: RetroColors.phosphorDim),
            ),
          ],
          const SizedBox(height: 8),
          SecondaryArcadeButton(
            label: playedToday ? 'PLAY DAILY AGAIN' : 'PLAY DAILY',
            color: RetroColors.zenBlue,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

// ─── Top 5 leaderboard ──────────────────────────────

class TopScoresList extends StatelessWidget {
  const TopScoresList({super.key, required this.scores});

  final List<ScoreEntry> scores;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TOP SCORES',
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < scores.length && i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: RetroText.pixel(
                      size: 7,
                      color: i == 0 ? RetroColors.amber : RetroColors.metal,
                    ),
                  ),
                ),
                Text(
                  scores[i].score.toString().padLeft(5, '0'),
                  style: RetroText.pixel(
                    size: 9,
                    color: i == 0 ? RetroColors.amber : RetroColors.phosphorDim,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'L${scores[i].level}',
                  style: RetroText.pixel(size: 7, color: RetroColors.metal),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
