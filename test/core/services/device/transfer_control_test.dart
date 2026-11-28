import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';

void main() {
  group('checkSpaceBudget', () {
    test('fits when the requirement equals the free space', () {
      final result = checkSpaceBudget(1000, 1000);

      expect(result.status, SpaceBudgetStatus.fits);
      expect(result.canProceed, isTrue);
      expect(result.freeBytes, 1000);
      expect(result.requiredBytes, 1000);
    });

    test('insufficient reports both numbers in the message', () {
      final result = checkSpaceBudget(500, 1500);

      expect(result.status, SpaceBudgetStatus.insufficient);
      expect(result.canProceed, isFalse);
      expect(result.message, contains('1500'));
      expect(result.message, contains('500'));
      expect(result.message, contains('需要'));
      expect(result.message, contains('可用'));
    });

    test('missing statvfs degrades to unknown instead of blocking', () {
      final result = checkSpaceBudget(null, 1500);

      expect(result.status, SpaceBudgetStatus.unknown);
      expect(result.canProceed, isTrue);
      expect(result.message, contains('跳过'));
    });

    test('a zeroed statvfs is treated as unknown, not zero free', () {
      // Several MicroPython ports report a zeroed tuple on an unmounted FS;
      // refusing every upload because of that would be wrong.
      expect(checkSpaceBudget(0, 10).status, SpaceBudgetStatus.unknown);
      expect(checkSpaceBudget(-1, 10).status, SpaceBudgetStatus.unknown);
    });

    test('a zero-byte requirement always fits', () {
      expect(checkSpaceBudget(0, 0).status, SpaceBudgetStatus.fits);
      expect(checkSpaceBudget(null, 0).status, SpaceBudgetStatus.fits);
    });
  });

  group('formatTransferBytes', () {
    test('formats each magnitude', () {
      expect(formatTransferBytes(0), '0 B');
      expect(formatTransferBytes(512), '512 B');
      expect(formatTransferBytes(1024), '1.0 KB');
      expect(formatTransferBytes(1024 * 1024), '1.0 MB');
      expect(formatTransferBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('runCancellableFileBatch', () {
    test('processes every item when not cancelled', () async {
      final token = FileTransferCancelToken();
      final processed = <int>[];

      final outcome = await runCancellableFileBatch<int>(
        items: [1, 2, 3],
        token: token,
        action: (item, index) async => processed.add(item),
      );

      expect(processed, [1, 2, 3]);
      expect(outcome.processed, 3);
      expect(outcome.cancelled, isFalse);
      expect(outcome.completedAll, isTrue);
    });

    test('stops before the next file once cancelled', () async {
      final token = FileTransferCancelToken();
      final processed = <int>[];

      final outcome = await runCancellableFileBatch<int>(
        items: [1, 2, 3, 4],
        token: token,
        action: (item, index) async {
          processed.add(item);
          // The user cancels while file 2 is in flight: file 2 must still
          // complete, file 3 must never start.
          if (item == 2) token.cancel();
        },
      );

      expect(processed, [1, 2]);
      expect(outcome.processed, 2);
      expect(outcome.cancelled, isTrue);
      expect(outcome.completedAll, isFalse);
    });

    test('cancelling before the first item runs nothing', () async {
      final token = FileTransferCancelToken()..cancel();
      var ran = 0;

      final outcome = await runCancellableFileBatch<int>(
        items: [1, 2],
        token: token,
        action: (item, index) async => ran++,
      );

      expect(ran, 0);
      expect(outcome.processed, 0);
      expect(outcome.cancelled, isTrue);
    });

    test('works with a null token (cancellation not wired)', () async {
      final outcome = await runCancellableFileBatch<int>(
        items: [1, 2],
        token: null,
        action: (item, index) async {},
      );

      expect(outcome.processed, 2);
    });

    test('shouldSkip items are not counted as processed', () async {
      final outcome = await runCancellableFileBatch<int>(
        items: [1, 2, 3],
        token: FileTransferCancelToken(),
        shouldSkip: (item, index) async => item == 2,
        action: (item, index) async {},
      );

      expect(outcome.processed, 2);
    });

    test('throwIfTransferCancelled throws a typed exception', () {
      final token = FileTransferCancelToken()..cancel();

      expect(
        () => throwIfTransferCancelled(token),
        throwsA(isA<FileTransferCancelledException>()),
      );
      expect(() => throwIfTransferCancelled(null), returnsNormally);
    });
  });
}
