import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

/// Forwards crashes to Sentry, in addition to keeping [LocalCrashReporter]'s
/// on-device log.
///
/// [recent]/[clear] delegate to [local] — Sentry has no on-device read API
/// (and doesn't need one), so the in-app "recent crashes" view a player can
/// be asked for still comes from local storage.
///
/// Construct this only once [SentryFlutter.init] has run (see `main.dart`);
/// [report] is a no-op from Sentry's side otherwise, and Sentry's SDK
/// tolerates calls before init by simply dropping the event.
class SentryCrashReporter implements CrashReporter {
  SentryCrashReporter({CrashReporter? local})
    : local = local ?? LocalCrashReporter();

  final CrashReporter local;

  @override
  Future<void> report(Object error, StackTrace stack, {String? context}) async {
    await local.report(error, stack, context: context);
    try {
      await Sentry.captureException(
        error,
        stackTrace: stack,
        hint: context == null ? null : Hint.withMap({'context': context}),
      );
    } catch (_) {
      // Reporting a crash must never cause one, and never take down the
      // local report above if Sentry itself is unreachable.
    }
  }

  @override
  Future<List<CrashRecord>> recent() => local.recent();

  @override
  Future<void> clear() => local.clear();
}

/// Initializes Sentry and installs crash handlers that report to it (plus
/// the local on-device log), if [dsn] is non-empty. Otherwise, installs
/// [LocalCrashReporter] alone — everything still works, just without any
/// off-device reporting.
///
/// [dsn] is meant to come from a build-time define, never hardcoded:
/// `flutter run --dart-define=SENTRY_DSN=<your dsn>`.
Future<void> initCrashReporting({
  required String dsn,
  required Future<void> Function(CrashReporter reporter) runWithReporter,
}) async {
  if (dsn.isEmpty) {
    await runWithReporter(LocalCrashReporter());
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = dsn;
    // No performance/session data beyond crash reports themselves.
    options.tracesSampleRate = 0.0;
  }, appRunner: () => runWithReporter(SentryCrashReporter()));
}
