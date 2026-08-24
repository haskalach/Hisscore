import 'package:shared_preferences/shared_preferences.dart';

abstract class HighScoreStore {
  Future<int> load();
  Future<void> save(int score);
}

class InMemoryHighScoreStore implements HighScoreStore {
  InMemoryHighScoreStore([this.value = 0]);

  int value;

  @override
  Future<int> load() async => value;

  @override
  Future<void> save(int score) async {
    if (score > value) {
      value = score;
    }
  }
}

class SharedPreferencesHighScoreStore implements HighScoreStore {
  SharedPreferencesHighScoreStore({this.key = 'hisscore.high_score'});

  static const defaultKey = 'hisscore.high_score';

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
}
