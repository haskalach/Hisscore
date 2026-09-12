import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules a local "come back for your streak" reminder after a daily
/// challenge run. No server or account needed — purely on-device.
///
/// Every call is best-effort: any platform without a working
/// notifications backend (or a test harness with no plugin registered)
/// just silently does nothing instead of crashing the game.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const _reminderId = 1001;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: iosSettings,
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService: init failed ($e)');
    }
  }

  /// Asks the OS for notification permission. Call this in response to
  /// a user action (e.g. finishing their first daily challenge), not on
  /// cold start — a permission prompt out of nowhere just gets denied.
  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('NotificationService: permission request failed ($e)');
    }
  }

  /// Schedules a single streak reminder about a day out, replacing any
  /// previously scheduled one. Uses a fixed offset rather than "same
  /// time tomorrow" in the device's exact local timezone — close enough
  /// for a daily nudge without pulling in a timezone-lookup plugin.
  Future<void> scheduleStreakReminder({required int streak}) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _reminderId);
      final when = tz.TZDateTime.now(tz.local).add(const Duration(hours: 20));
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_streak',
          'Daily streak reminders',
          channelDescription:
              "Reminds you to keep your Hisscore daily streak alive",
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        id: _reminderId,
        title: 'Your snake misses you 🐍',
        body: streak > 1
            ? "Day $streak streak — don't break it!"
            : "Come back for today's daily challenge.",
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('NotificationService: schedule failed ($e)');
    }
  }

  Future<void> cancelReminder() async {
    try {
      await _plugin.cancel(id: _reminderId);
    } catch (_) {}
  }
}
