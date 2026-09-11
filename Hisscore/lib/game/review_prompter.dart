import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks the OS for an app-store rating at a moment the player is likely
/// feeling good about the game (a new high score) — and only once ever,
/// so it never nags. The OS itself further limits how often the actual
/// dialog can appear, regardless of how often this is called.
class ReviewPrompter {
  static const _promptedKey = 'hisscore.has_prompted_review';

  /// Requests a review if [gamesPlayed] clears a small minimum (so the
  /// very first game doesn't trigger it) and we haven't asked before.
  Future<void> maybePrompt({required int gamesPlayed}) async {
    if (gamesPlayed < 2) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_promptedKey) ?? false) return;

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      await review.requestReview();
      await prefs.setBool(_promptedKey, true);
    } catch (e) {
      debugPrint('ReviewPrompter: request failed ($e)');
    }
  }
}
