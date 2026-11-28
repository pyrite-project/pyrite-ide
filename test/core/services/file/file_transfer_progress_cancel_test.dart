import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/transfer_control.dart';
import 'package:pyrite_ide/core/services/file/file_ops.dart';

void main() {
  // The notifier schedules a timer to clear the finished state; the test
  // binding must be initialised so timers are allowed, and each test disposes
  // the notifier to cancel it.
  TestWidgetsFlutterBinding.ensureInitialized();

  FileTransferProgressNotifier createNotifier() {
    final notifier = FileTransferProgressNotifier();
    addTearDown(notifier.dispose);
    return notifier;
  }

  group('FileTransferProgressNotifier cancellation', () {
    test('start creates a fresh, uncancelled token', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.folder,
        totalFiles: 3,
      );

      final token = notifier.beginCancelToken();

      expect(token.isCancelled, isFalse);
      expect(notifier.state.cancelled, isFalse);
      expect(notifier.state.canCancel, isTrue);
    });

    test('requestCancel flips the token and marks the state', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.folder,
        totalFiles: 3,
      );
      final token = notifier.beginCancelToken();

      notifier.requestCancel();

      expect(token.isCancelled, isTrue);
      expect(notifier.state.cancelRequested, isTrue);
      expect(notifier.state.canCancel, isFalse);
    });

    test('a new batch does not inherit the previous cancellation', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.file,
        totalFiles: 1,
      );
      notifier.requestCancel();
      notifier.cancelledByUser();

      notifier.start(
        direction: FileTransferDirection.download,
        scope: FileTransferScope.file,
        totalFiles: 1,
      );

      expect(notifier.beginCancelToken().isCancelled, isFalse);
      expect(notifier.state.cancelRequested, isFalse);
      expect(notifier.state.cancelled, isFalse);
    });

    test('cancelledByUser resets the byte counters and flags the state', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.folder,
        totalFiles: 4,
      );
      notifier.startFile(
        file: '/local/a.py',
        index: 2,
        totalFiles: 4,
        bytesTotal: 1000,
      );
      notifier.updateBytes(400, 1000);
      notifier.requestCancel();

      notifier.cancelledByUser(message: '已取消');

      expect(notifier.state.cancelled, isTrue);
      expect(notifier.state.cancelRequested, isFalse);
      expect(notifier.state.bytesDone, 0);
      expect(notifier.state.message, '已取消');
      expect(notifier.cancelToken, isNull);
    });

    test('complete clears the token so a stale cancel cannot fire', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.file,
        totalFiles: 1,
      );
      notifier.complete(message: 'done');

      expect(notifier.cancelToken, isNull);
      // A later requestCancel on an idle/completed state must not throw.
      expect(notifier.requestCancel, returnsNormally);
    });

    test('requestCancel is ignored once the transfer failed', () {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.file,
        totalFiles: 1,
      );
      final token = notifier.beginCancelToken();
      notifier.fail('boom');

      notifier.requestCancel();

      expect(token.isCancelled, isFalse);
      expect(notifier.state.failed, isTrue);
    });

    test('canCancel is false while inactive', () {
      final notifier = createNotifier();
      expect(notifier.state.canCancel, isFalse);
    });
  });

  group('cancellation stops a batch and leaves state clean', () {
    test('loop stops early, state is reset, device is not aborted', () async {
      final notifier = createNotifier();
      notifier.start(
        direction: FileTransferDirection.upload,
        scope: FileTransferScope.folder,
        totalFiles: 3,
      );
      final token = notifier.beginCancelToken();
      final visited = <String>[];

      final outcome = await runCancellableFileBatch<String>(
        items: ['a.py', 'b.py', 'c.py'],
        token: token,
        action: (file, index) async {
          visited.add(file);
          notifier.startFile(
            file: file,
            index: index + 1,
            totalFiles: 3,
            bytesTotal: 10,
          );
          notifier.updateBytes(10, 10);
          if (file == 'a.py') notifier.requestCancel();
        },
      );

      expect(visited, ['a.py']);
      expect(outcome.cancelled, isTrue);
      expect(outcome.processed, 1);
      // No CTRL-C / transaction abort was needed: the loop simply stopped.
      notifier.cancelledByUser();
      expect(notifier.state.cancelled, isTrue);
      expect(notifier.state.isActive, isTrue);
    });
  });
}
