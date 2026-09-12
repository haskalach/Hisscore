import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/high_score_store.dart';
import 'package:hisscore/game/snake_engine.dart';

void main() {
  group('ScoreEntry', () {
    test('survives a JSON round trip', () {
      const entry = ScoreEntry(score: 1234, level: 7, mode: 'HARDCORE');
      final restored = ScoreEntry.fromJson(entry.toJson());
      expect(restored.score, 1234);
      expect(restored.level, 7);
      expect(restored.mode, 'HARDCORE');
    });

    test('falls back to sane values on missing fields', () {
      final restored = ScoreEntry.fromJson(<String, dynamic>{});
      expect(restored.score, 0);
      expect(restored.level, 1);
      expect(restored.mode, 'CLASSIC');
    });
  });

  group('GameStats', () {
    test('survives a JSON round trip', () {
      final stats = GameStats(gamesPlayed: 9, totalApples: 120, bestCombo: 5);
      final restored = GameStats.fromJson(stats.toJson());
      expect(restored.gamesPlayed, 9);
      expect(restored.totalApples, 120);
      expect(restored.bestCombo, 5);
    });

    test('falls back to zeroes on missing fields', () {
      final restored = GameStats.fromJson(<String, dynamic>{});
      expect(restored.gamesPlayed, 0);
      expect(restored.totalApples, 0);
      expect(restored.bestCombo, 0);
    });
  });

  group('DailyState', () {
    test('survives a JSON round trip', () {
      const state = DailyState(
        lastPlayedKey: '2026-05-10',
        lastScore: 450,
        currentStreak: 3,
        bestStreak: 8,
      );
      final restored = DailyState.fromJson(state.toJson());
      expect(restored.lastPlayedKey, '2026-05-10');
      expect(restored.lastScore, 450);
      expect(restored.currentStreak, 3);
      expect(restored.bestStreak, 8);
    });

    test('starts empty when nothing has been played', () {
      final restored = DailyState.fromJson(<String, dynamic>{});
      expect(restored.lastPlayedKey, isNull);
      expect(restored.lastScore, 0);
      expect(restored.currentStreak, 0);
      expect(restored.bestStreak, 0);
    });
  });

  group('InMemoryHighScoreStore', () {
    test('keeps only the best score', () async {
      final store = InMemoryHighScoreStore();
      await store.save(100);
      await store.save(50); // lower, ignored
      expect(await store.load(), 100);
    });

    test('ranks top scores highest first', () async {
      final store = InMemoryHighScoreStore();
      for (final score in [30, 10, 50, 20]) {
        await store.saveScoreEntry(ScoreEntry(score: score));
      }
      final scores = await store.loadTopScores();
      expect(scores.map((e) => e.score), [50, 30, 20, 10]);
    });

    test('keeps at most five entries, dropping the weakest', () async {
      final store = InMemoryHighScoreStore();
      for (var score = 10; score <= 80; score += 10) {
        await store.saveScoreEntry(ScoreEntry(score: score));
      }
      final scores = await store.loadTopScores();
      expect(scores, hasLength(5));
      expect(scores.map((e) => e.score), [80, 70, 60, 50, 40]);
    });

    test('a leaderboard entry also lifts the high score', () async {
      final store = InMemoryHighScoreStore();
      await store.saveScoreEntry(const ScoreEntry(score: 777));
      expect(await store.load(), 777);
    });

    test('accumulates stats across runs', () async {
      final store = InMemoryHighScoreStore();
      final engine = SnakeEngine(random: Random(1))..start();
      // Force a couple of runs' worth of numbers onto the engine.
      engine.totalApplesEaten = 12;
      engine.bestCombo = 4;
      await store.updateStats(engine);

      engine.totalApplesEaten = 5;
      engine.bestCombo = 2; // lower, shouldn't replace the best
      await store.updateStats(engine);

      final stats = await store.loadStats();
      expect(stats.gamesPlayed, 2);
      expect(stats.totalApples, 17);
      expect(stats.bestCombo, 4);
    });

    test('round-trips daily state', () async {
      final store = InMemoryHighScoreStore();
      expect((await store.loadDailyState()).currentStreak, 0);

      await store.saveDailyState(
        const DailyState(
          lastPlayedKey: '2026-05-10',
          lastScore: 120,
          currentStreak: 2,
          bestStreak: 6,
        ),
      );

      final state = await store.loadDailyState();
      expect(state.lastPlayedKey, '2026-05-10');
      expect(state.currentStreak, 2);
      expect(state.bestStreak, 6);
    });
  });
}
