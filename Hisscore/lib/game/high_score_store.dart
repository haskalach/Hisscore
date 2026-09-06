import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'snake_engine.dart';

// ─── Score entry for the top-5 leaderboard ──────────

class ScoreEntry {
  const ScoreEntry({
    required this.score,
    this.level = 1,
    this.mode = 'CLASSIC',
  });

  final int score;
  final int level;
  final String mode;

  Map<String, dynamic> toJson() => {
    'score': score,
    'level': level,
    'mode': mode,
  };

  factory ScoreEntry.fromJson(Map<String, dynamic> json) => ScoreEntry(
    score: json['score'] as int? ?? 0,
    level: json['level'] as int? ?? 1,
    mode: json['mode'] as String? ?? 'CLASSIC',
  );
}

// ─── Cumulative stats ───────────────────────────────

class GameStats {
  GameStats({
    this.gamesPlayed = 0,
    this.totalApples = 0,
    this.bestCombo = 0,
  });

  int gamesPlayed;
  int totalApples;
  int bestCombo;

  Map<String, dynamic> toJson() => {
    'gamesPlayed': gamesPlayed,
    'totalApples': totalApples,
    'bestCombo': bestCombo,
  };

  factory GameStats.fromJson(Map<String, dynamic> json) => GameStats(
    gamesPlayed: json['gamesPlayed'] as int? ?? 0,
    totalApples: json['totalApples'] as int? ?? 0,
    bestCombo: json['bestCombo'] as int? ?? 0,
  );
}

// ─── Abstract store ─────────────────────────────────

abstract class HighScoreStore {
  Future<int> load();
  Future<void> save(int score);
  Future<List<ScoreEntry>> loadTopScores();
  Future<void> saveScoreEntry(ScoreEntry entry);
  Future<GameStats> loadStats();
  Future<void> updateStats(SnakeEngine engine);
}

// ─── In-memory (testing) ────────────────────────────

class InMemoryHighScoreStore implements HighScoreStore {
  InMemoryHighScoreStore([this.value = 0]);

  int value;
  final List<ScoreEntry> _scores = [];
  final GameStats _stats = GameStats();

  @override
  Future<int> load() async => value;

  @override
  Future<void> save(int score) async {
    if (score > value) {
      value = score;
    }
  }

  @override
  Future<List<ScoreEntry>> loadTopScores() async =>
      List.of(_scores)..sort((a, b) => b.score.compareTo(a.score));

  @override
  Future<void> saveScoreEntry(ScoreEntry entry) async {
    _scores.add(entry);
    _scores.sort((a, b) => b.score.compareTo(a.score));
    while (_scores.length > 5) {
      _scores.removeLast();
    }
    if (entry.score > value) {
      value = entry.score;
    }
  }

  @override
  Future<GameStats> loadStats() async => _stats;

  @override
  Future<void> updateStats(SnakeEngine engine) async {
    _stats.gamesPlayed++;
    _stats.totalApples += engine.totalApplesEaten;
    if (engine.bestCombo > _stats.bestCombo) {
      _stats.bestCombo = engine.bestCombo;
    }
  }
}

// ─── SharedPreferences (production) ─────────────────

class SharedPreferencesHighScoreStore implements HighScoreStore {
  SharedPreferencesHighScoreStore({this.key = 'hisscore.high_score'});

  static const defaultKey = 'hisscore.high_score';
  static const _topScoresKey = 'hisscore.top_scores';
  static const _statsKey = 'hisscore.stats';

  final String key;
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<int> load() async {
    await init();
    return _prefs!.getInt(key) ?? 0;
  }

  @override
  Future<void> save(int score) async {
    await init();
    final current = _prefs!.getInt(key) ?? 0;
    if (score > current) {
      await _prefs!.setInt(key, score);
    }
  }

  @override
  Future<List<ScoreEntry>> loadTopScores() async {
    await init();
    final raw = _prefs!.getString(_topScoresKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ScoreEntry.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveScoreEntry(ScoreEntry entry) async {
    await init();
    final scores = await loadTopScores();
    scores.add(entry);
    scores.sort((a, b) => b.score.compareTo(a.score));
    final top5 = scores.take(5).toList();
    await _prefs!.setString(
      _topScoresKey,
      jsonEncode(top5.map((e) => e.toJson()).toList()),
    );
    // Also update the legacy single high score.
    await save(entry.score);
  }

  @override
  Future<GameStats> loadStats() async {
    await init();
    final raw = _prefs!.getString(_statsKey);
    if (raw == null) return GameStats();
    try {
      return GameStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return GameStats();
    }
  }

  @override
  Future<void> updateStats(SnakeEngine engine) async {
    await init();
    final stats = await loadStats();
    stats.gamesPlayed++;
    stats.totalApples += engine.totalApplesEaten;
    if (engine.bestCombo > stats.bestCombo) {
      stats.bestCombo = engine.bestCombo;
    }
    await _prefs!.setString(_statsKey, jsonEncode(stats.toJson()));
  }
}
