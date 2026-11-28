import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/flutter/error_log_dedupe.dart';

void main() {
  const quiet = Duration(milliseconds: 40);

  late ErrorLogDedupe dedupe;
  late List<String> summaries;

  setUp(() {
    summaries = [];
    dedupe = ErrorLogDedupe(emitSummary: summaries.add, quiet: quiet);
    addTearDown(dedupe.dispose);
  });

  Future<void> settle() =>
      Future<void>.delayed(quiet + const Duration(milliseconds: 60));

  test('first report is logged, repeats are folded into one summary', () async {
    expect(dedupe.admit(signature: 'assertion'), isTrue);
    for (var i = 0; i < 5; i++) {
      expect(dedupe.admit(signature: 'assertion'), isFalse);
    }
    expect(summaries, isEmpty, reason: 'the burst has not settled yet');

    await settle();

    expect(summaries, hasLength(1));
    expect(summaries.single, contains('repeated 5 time(s)'));
    expect(summaries.single, contains('assertion'));
  });

  test('a burst still running writes no tally', () async {
    expect(dedupe.admit(signature: 'assertion'), isTrue);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(dedupe.admit(signature: 'assertion'), isFalse);
    }
    expect(summaries, isEmpty);

    await settle();

    expect(summaries.single, contains('repeated 6 time(s)'));
  });

  test('distinct messages are reported in full', () async {
    expect(dedupe.admit(signature: 'first'), isTrue);
    expect(dedupe.admit(signature: 'second'), isTrue);
    expect(dedupe.admit(signature: 'first'), isFalse);

    await settle();

    expect(summaries, hasLength(1));
    expect(summaries.single, contains('repeated 1 time(s)'));
    expect(summaries.single, contains('first'));
  });

  test('flush reports pending tallies without waiting', () async {
    expect(dedupe.admit(signature: 'assertion'), isTrue);
    dedupe.admit(signature: 'assertion');
    dedupe.admit(signature: 'assertion');

    dedupe.flush();

    expect(summaries.single, contains('repeated 2 time(s)'));
    await settle();
    expect(summaries, hasLength(1), reason: 'the timer must not fire twice');
  });

  test('reset drops pending tallies', () async {
    expect(dedupe.admit(signature: 'assertion'), isTrue);
    dedupe.admit(signature: 'assertion');

    dedupe.reset();
    await settle();

    expect(summaries, isEmpty);
    expect(dedupe.admit(signature: 'assertion'), isTrue);
  });

  test('long messages are shortened in the tally', () async {
    final longSignature = 'x' * 400;
    expect(dedupe.admit(signature: longSignature), isTrue);
    dedupe.admit(signature: longSignature);

    dedupe.flush();

    expect(summaries.single.length, lessThan(longSignature.length));
    expect(summaries.single, endsWith('...'));
  });
}
