import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';

void main() {
  late IdeMessageNotifier notifier;

  setUp(() {
    notifier = IdeMessageNotifier();
  });

  tearDown(() {
    // Cancels the pending auto-dismiss timers this test created.
    notifier.dispose();
  });

  group('defaults', () {
    test('duration and closeable follow the message type', () {
      notifier.success('saved');
      notifier.info('heads up');
      notifier.warning('careful');
      notifier.error('failed');

      final success = notifier.state[0];
      final info = notifier.state[1];
      final warning = notifier.state[2];
      final error = notifier.state[3];

      expect(success.type, IdeMessageType.success);
      expect(success.duration, const Duration(seconds: 3));
      expect(success.closeable, isFalse);

      expect(info.type, IdeMessageType.info);
      expect(info.duration, const Duration(seconds: 4));
      expect(info.closeable, isFalse);

      expect(warning.type, IdeMessageType.warning);
      expect(warning.duration, const Duration(seconds: 6));
      expect(warning.closeable, isTrue);

      expect(error.type, IdeMessageType.error);
      expect(error.duration, const Duration(seconds: 8));
      expect(error.closeable, isTrue);
    });

    test('explicit duration and closeable override the type defaults', () {
      notifier.show(
        'custom',
        type: IdeMessageType.error,
        duration: const Duration(seconds: 2),
        closeable: false,
      );

      final entry = notifier.state.single;
      expect(entry.duration, const Duration(seconds: 2));
      expect(entry.closeable, isFalse);
    });

    test('ignores empty messages', () {
      notifier.info('');
      notifier.error('');
      expect(notifier.state, isEmpty);
    });
  });

  group('dedupe', () {
    test('repeating the same message and type refreshes one entry', () {
      notifier.info('same');
      final id = notifier.state.single.id;

      notifier.show('same', duration: const Duration(seconds: 10));

      expect(notifier.state, hasLength(1));
      expect(notifier.state.single.id, id);
      expect(notifier.state.single.duration, const Duration(seconds: 10));
    });

    test('same text with a different type is a separate entry', () {
      notifier.info('same');
      notifier.warning('same');

      expect(notifier.state, hasLength(2));
      expect(notifier.state[0].type, IdeMessageType.info);
      expect(notifier.state[1].type, IdeMessageType.warning);
    });

    test('dedupe keeps the refreshed entry at its original position', () {
      notifier.info('first');
      notifier.success('second');

      notifier.show('first', closeable: true);

      expect(notifier.state.map((entry) => entry.message), ['first', 'second']);
      expect(notifier.state.first.closeable, isTrue);
    });
  });

  group('visible cap', () {
    test('maxVisible is four', () {
      expect(IdeMessageNotifier.maxVisible, 4);
    });

    test('adding a fifth message evicts the oldest', () {
      for (var index = 0; index < 5; index++) {
        notifier.info('message $index');
      }

      expect(notifier.state, hasLength(4));
      expect(notifier.state.map((entry) => entry.message), [
        'message 1',
        'message 2',
        'message 3',
        'message 4',
      ]);
    });

    test('the oldest entries are evicted first across types', () {
      notifier.info('one');
      notifier.success('two');
      notifier.warning('three');
      notifier.error('four');
      notifier.info('five');

      expect(notifier.state.map((entry) => entry.message), [
        'two',
        'three',
        'four',
        'five',
      ]);
    });
  });

  test('dismiss removes a single entry', () {
    notifier.info('first');
    notifier.info('second');

    notifier.dismiss(notifier.state.first.id);

    expect(notifier.state.single.message, 'second');
  });
}
