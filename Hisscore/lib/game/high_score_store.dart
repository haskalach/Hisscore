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

// ─── Daily challenge state ───────────────────────────

class DailyState {
  const DailyState({
    this.lastPlayedKey,
    this.lastScore = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
  });

  /// dateKey (e.g. "2026-03-14") of the last completed daily run.
  final String? lastPlayedKey;
  final int lastScore;
  final int currentStreak;
  final int bestStreak;

  Map<String, dynamic> toJson() => {
    'lastPlayedKey': lastPlayedKey,
    'lastScore': lastScore,
    'currentStreak': currentStreak,
    'bestStreak': bestStreak,
  };

  factory DailyState.fromJson(Map<String, dynamic> json) => DailyState(
    lastPlayedKey: json['lastPlayedKey'] as String?,
    lastScore: json['lastScore'] as int? ?? 0,
    currentStreak: json['currentStreak'] as int? ?? 0,
    bestStreak: json['bestStreak'] as int? ?? 0,
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
  Future<DailyState> loadDailyState();
  Future<void> saveDailyState(DailyState state);
}

// ─── In-memory (testing) ────────────────────────────

class InMemoryHighScoreStore implements HighScoreStore {
  InMemoryHighScoreStore([this.value = 0]);

  int value;
  final List<ScoreEntry> _scores = [];
  final GameStats _stats = GameStats();
  DailyState _daily = const DailyState();

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

  @override
  Future<DailyState> loadDailyState() async => _daily;

  @override
  Future<void> saveDailyState(DailyState state) async => _daily = state;
}

// ─── SharedPreferences (production) ─────────────────

class SharedPreferencesHighScoreStore implements HighScoreStore {
  SharedPreferencesHighScoreStore({this.key = 'hisscore.high_score'});

  static const defaultKey = 'hisscore.high_score';
  static const _topScoresKey = 'hisscore.top_scores';
  static const _statsKey = 'hisscore.stats';
  static const _dailyKey = 'hisscore.daily_state';

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

  @override
  Future<DailyState> loadDailyState() async {
    await init();
    final raw = _prefs!.getString(_dailyKey);
    if (raw == null) return const DailyState();
    try {
      return DailyState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const DailyState();
    }
  }

  @override
  Future<void> saveDailyState(DailyState state) async {
    await init();
    await _prefs!.setString(_dailyKey, jsonEncode(state.toJson()));
  }
}
