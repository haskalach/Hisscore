import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/crash_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('CrashRecord survives a JSON round trip', () {
    final record = CrashRecord(
      at: DateTime.utc(2026, 5, 10, 12, 30),
      error: 'Bad thing',
      stack: '#0 somewhere',
      context: 'flutter',
    );
    final restored = CrashRecord.fromJson(record.toJson());
    expect(restored.at, record.at);
    expect(restored.error, 'Bad thing');
    expect(restored.stack, '#0 somewhere');
    expect(restored.context, 'flutter');
  });

  test('records a failure and reads it back', () async {
    final reporter = LocalCrashReporter();
    await reporter.report(
      StateError('boom'),
      StackTrace.current,
      context: 'test',
    );

    final recent = await reporter.recent();
    expect(recent, hasLength(1));
    expect(recent.single.error, contains('boom'));
    expect(recent.single.context, 'test');
  });

  test('keeps the newest first', () async {
    final reporter = LocalCrashReporter();
    await reporter.report(StateError('first'), StackTrace.current);
    await reporter.report(StateError('second'), StackTrace.current);

    final recent = await reporter.recent();
    expect(recent.first.error, contains('second'));
    expect(recent.last.error, contains('first'));
  });

  test('drops the oldest past the cap', () async {
    final reporter = LocalCrashReporter(maxRecords: 3);
    for (var i = 0; i < 5; i++) {
      await reporter.report(StateError('error $i'), StackTrace.current);
    }

    final recent = await reporter.recent();
    expect(recent, hasLength(3));
    expect(recent.first.error, contains('error 4'));
    expect(
      recent.map((r) => r.error).join(),
      isNot(contains('error 0')),
      reason: 'the oldest should have been dropped',
    );
  });

  test('trims enormous stacks instead of storing them whole', () async {
    final reporter = LocalCrashReporter();
    final hugeStack = StackTrace.fromString(
      List.generate(200, (i) => '#$i frame').join('\n'),
    );
    await reporter.report(StateError('deep'), hugeStack);

    final stored = (await reporter.recent()).single.stack;
    expect(stored, contains('more'));
    expect('\n'.allMatches(stored).length, lessThan(40));
  });

  test('clear empties the log', () async {
    final reporter = LocalCrashReporter();
    await reporter.report(StateError('boom'), StackTrace.current);
    expect(await reporter.recent(), isNotEmpty);

    await reporter.clear();
    expect(await reporter.recent(), isEmpty);
  });

  test('survives a corrupt log rather than throwing', () async {
    SharedPreferences.setMockInitialValues({
      'hisscore.crash_log': 'not json at all',
    });
    expect(await LocalCrashReporter().recent(), isEmpty);
  });

  test('the no-op reporter records nothing', () async {
    const reporter = NoopCrashReporter();
    await reporter.report(StateError('boom'), StackTrace.current);
    expect(await reporter.recent(), isEmpty);
  });
}
