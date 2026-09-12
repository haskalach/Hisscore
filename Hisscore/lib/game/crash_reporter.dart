import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded failure.
class CrashRecord {
  const CrashRecord({
    required this.at,
    required this.error,
    required this.stack,
    this.context,
  });

  final DateTime at;
  final String error;
  final String stack;

  /// Where it came from — 'flutter', 'platform', 'zone', or a caller's
  /// own label.
  final String? context;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'error': error,
    'stack': stack,
    'context': context,
  };

  factory CrashRecord.fromJson(Map<String, dynamic> json) => CrashRecord(
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(1970),
    error: json['error'] as String? ?? '',
    stack: json['stack'] as String? ?? '',
    context: json['context'] as String?,
  );

  @override
  String toString() =>
      '[${at.toIso8601String()}]${context == null ? '' : ' ($context)'} '
      '$error';
}

/// Where crashes go.
///
/// The app deliberately has no third-party crash SDK: Crashlytics wants
/// a Firebase project and Sentry wants a DSN, and neither belongs in
/// the repo. This is the seam for one — swap the implementation and
/// every call site already reports.
abstract class CrashReporter {
  Future<void> report(Object error, StackTrace stack, {String? context});
  Future<List<CrashRecord>> recent();
  Future<void> clear();
}

/// Keeps the last few failures on the device.
///
/// Not a substitute for a real reporter — nothing is sent anywhere —
/// but it means a crash leaves a trace you can ask a player for
/// instead of vanishing into the console.
class LocalCrashReporter implements CrashReporter {
  LocalCrashReporter({this.maxRecords = 20});

  static const _key = 'hisscore.crash_log';

  final int maxRecords;

  @override
  Future<void> report(Object error, StackTrace stack, {String? context}) async {
    // Always surface it in the console for a developer watching.
    debugPrint('CrashReporter${context == null ? '' : ' ($context)'}: $error');
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = await _read(prefs)
        ..insert(
          0,
          CrashRecord(
            at: DateTime.now(),
            error: error.toString(),
            // Stacks can be enormous; the top frames are the useful part.
            stack: _trim(stack.toString()),
            context: context,
          ),
        );
      final kept = records.take(maxRecords).toList();
      await prefs.setString(
        _key,
        jsonEncode(kept.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      // Reporting a crash must never cause one.
      debugPrint('CrashReporter: could not record ($e)');
    }
  }

  @override
  Future<List<CrashRecord>> recent() async {
    try {
      return _read(await SharedPreferences.getInstance());
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  Future<List<CrashRecord>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => CrashRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt log is worth less than a working app.
      return [];
    }
  }

  static String _trim(String stack, {int lines = 25}) {
    final split = const LineSplitter().convert(stack);
    if (split.length <= lines) return stack;
    return '${split.take(lines).join('\n')}\n… ${split.length - lines} more';
  }
}

/// Throws everything away. Used by tests so they don't touch storage.
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  Future<void> report(
    Object error,
    StackTrace stack, {
    String? context,
  }) async {}

  @override
  Future<List<CrashRecord>> recent() async => const [];

  @override
  Future<void> clear() async {}
}

/// Routes Flutter's own error channels into [reporter].
///
/// Without this, a widget error prints a red box in debug and is
/// swallowed in release, and an async error outside the framework
/// takes the isolate down with nothing recorded.
void installCrashHandlers(CrashReporter reporter) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    unawaited(
      reporter.report(
        details.exception,
        details.stack ?? StackTrace.current,
        context: 'flutter',
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reporter.report(error, stack, context: 'platform'));
    // Returning true marks it handled so the app keeps running.
    return true;
  };
}
