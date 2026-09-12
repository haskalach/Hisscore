/// Pure logic for the daily challenge: everyone who plays on the same
/// calendar day gets the same food/obstacle layout (via a shared RNG
/// seed), and playing on consecutive days builds a streak.
///
/// No Flutter dependency, like snake_engine.dart — this is plain date
/// arithmetic and string keys, easy to unit test.
abstract final class DailyChallenge {
  /// The Snake game's own "epoch" — day 1 of the daily challenge.
  /// Arbitrary, just needs to be fixed so day numbers are stable.
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  /// A stable per-day identifier, e.g. "2026-03-14". Two devices on the
  /// same calendar day (UTC) produce the same key.
  static String dateKey(DateTime date) {
    final d = date.toUtc();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Day number since [epoch] (day 1 = the epoch date itself). Used both
  /// as the shareable "Daily #N" label and as the RNG seed, so every
  /// player on the same day sees the same board.
  static int dayNumber(DateTime date) {
    final today = DateTime.utc(
      date.toUtc().year,
      date.toUtc().month,
      date.toUtc().day,
    );
    return today.difference(epoch).inDays + 1;
  }

  /// Deterministic RNG seed for a given day number.
  static int seedForDay(int dayNumber) => dayNumber * 2654435761 & 0x7FFFFFFF;

  /// Computes the new streak count given the last day the challenge was
  /// completed and today's date.
  ///
  /// - Same day as last played: streak is unchanged (already counted).
  /// - Exactly one day after last played: streak continues (+1).
  /// - Any gap, or no previous play: streak restarts at 1.
  static int nextStreak({
    required String? lastPlayedKey,
    required int previousStreak,
    required DateTime today,
  }) {
    final todayKey = dateKey(today);
    if (lastPlayedKey == todayKey) return previousStreak;
    final yesterday = today.toUtc().subtract(const Duration(days: 1));
    if (lastPlayedKey == dateKey(yesterday)) return previousStreak + 1;
    return 1;
  }

  /// Whether the daily challenge has already been completed today.
  static bool playedToday({
    required String? lastPlayedKey,
    required DateTime today,
  }) {
    return lastPlayedKey == dateKey(today);
  }
}
