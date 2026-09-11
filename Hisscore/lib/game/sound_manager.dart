import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays the game's short retro sound effects (see tool/generate_sfx.dart)
/// and persists a mute toggle. Every call is best-effort: a missing audio
/// backend (e.g. a platform without one, or a test harness) never crashes
/// the game — it just plays silently.
class SoundManager {
  SoundManager();

  static const _enabledKey = 'hisscore.sound_enabled';

  bool _enabled = true;
  bool get enabled => _enabled;

  final Map<String, AudioPool> _pools = {};

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
    } catch (_) {
      // Local storage unavailable — default to enabled, just don't persist.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {
      // Best-effort; the in-memory toggle still applies this session.
    }
  }

  Future<void> playEat() => _play('eat');
  Future<void> playBonus() => _play('bonus');
  Future<void> playLevelUp() => _play('levelup');
  Future<void> playGameOver() => _play('gameover');

  Future<void> _play(String name) async {
    if (!_enabled) return;
    try {
      final pool = await _poolFor(name);
      await pool.start();
    } catch (e) {
      // No audio backend on this platform/harness — ignore.
      debugPrint('SoundManager: could not play $name ($e)');
    }
  }

  Future<AudioPool> _poolFor(String name) async {
    final existing = _pools[name];
    if (existing != null) return existing;
    final pool = await AudioPool.createFromAsset(
      path: 'sfx/$name.wav',
      maxPlayers: 3,
      playerMode: PlayerMode.lowLatency,
    );
    _pools[name] = pool;
    return pool;
  }

  Future<void> dispose() async {
    for (final pool in _pools.values) {
      try {
        await pool.dispose();
      } catch (_) {}
    }
    _pools.clear();
  }
}
