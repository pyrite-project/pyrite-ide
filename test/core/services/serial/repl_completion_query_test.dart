import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/device_executor.dart';

void main() {
  test('builds a bounded global completion probe', () {
    final command = buildReplCompletionProbe(null);

    expect(command, contains("dir()"));
    expect(command, contains('__PYRITE_COMPLETION__'));
    expect(command, endsWith('\r\n'));
  });

  test('builds a direct-owner probe and rejects code expressions', () {
    expect(buildReplCompletionProbe('machine'), contains('dir(machine)'));
    expect(() => buildReplCompletionProbe('machine.Pin'), throwsArgumentError);
    expect(
      () => buildReplCompletionProbe('machine.Pin()'),
      throwsArgumentError,
    );
  });

  test('extracts and filters the marker response', () {
    final response = '''
print('__PYRITE_COMPLETION__'+...)
__PYRITE_COMPLETION__["z", "__private", "a", "a"]
>>> 
''';

    expect(parseReplCompletionProbeResponse(response), ['a', 'z']);
  });

  test('returns null for missing or malformed marker data', () {
    expect(parseReplCompletionProbeResponse('>>> '), isNull);
    expect(
      parseReplCompletionProbeResponse('__PYRITE_COMPLETION__not-json\n>>> '),
      isNull,
    );
  });

  test(
    'tryRunExclusive declines while another action owns the mutex',
    () async {
      final mutex = ReplMutex();
      final release = Future<void>.delayed(const Duration(milliseconds: 20));
      final first = mutex.runExclusive<void>(() => release);

      expect(
        await mutex.tryRunExclusive<String>(() async => 'blocked'),
        isNull,
      );
      await first;
      expect(await mutex.tryRunExclusive<String>(() async => 'ok'), 'ok');
    },
  );
}
