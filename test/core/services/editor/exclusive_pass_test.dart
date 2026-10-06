import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/exclusive_pass.dart';

void main() {
  group('ExclusivePass', () {
    test(
      'a second pass does not start while the first is still running',
      () async {
        final gate = ExclusivePass();
        final firstGate = Completer<void>();
        final order = <String>[];

        final first = gate.run(() async {
          order.add('first started');
          await firstGate.future;
          order.add('first finished');
          return 1;
        });
        final second = gate.run(() async {
          order.add('second started');
          return 2;
        });

        // The second pass is queued, not running: two passes at once is exactly
        // what let a second copy of the same dialog stack on the first.
        expect(gate.isBusy, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(order, ['first started']);

        firstGate.complete();
        expect(await first, 1);
        expect(await second, 2);
        expect(order, ['first started', 'first finished', 'second started']);
        expect(gate.isBusy, isFalse);
      },
    );

    test('runIfIdle drops a request while a pass is in flight', () async {
      final gate = ExclusivePass();
      final firstGate = Completer<void>();
      var ran = 0;

      final first = gate.run(() async {
        ran++;
        await firstGate.future;
      });
      // A burst of focus events during a prompt: each of these is worthless,
      // because the pass already in flight is looking at the same files.
      final dropped = await Future.wait([
        gate.runIfIdle(() async => ran++),
        gate.runIfIdle(() async => ran++),
        gate.runIfIdle(() async => ran++),
      ]);
      expect(dropped, [null, null, null]);

      firstGate.complete();
      await first;
      expect(ran, 1);
    });

    test('runIfIdle still runs when nothing is in flight', () async {
      final gate = ExclusivePass();
      expect(await gate.runIfIdle(() async => 'done'), 'done');
    });

    test(
      'a pass that throws does not wedge the ones queued behind it',
      () async {
        final gate = ExclusivePass();

        final failing = gate.run<void>(() async => throw StateError('boom'));
        final following = gate.run(() async => 'ran anyway');

        await expectLater(failing, throwsStateError);
        expect(await following, 'ran anyway');
        expect(gate.isBusy, isFalse);
      },
    );
  });
}
