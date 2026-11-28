import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/logging/app_log.dart';

void main() {
  setUp(AppLog.resetThrottles);

  group('humanBytes', () {
    test('keeps small sizes in bytes', () {
      expect(AppLog.humanBytes(0), '0B');
      expect(AppLog.humanBytes(1023), '1023B');
    });

    test('scales to KB and MB', () {
      expect(AppLog.humanBytes(2048), '2.0KB');
      expect(AppLog.humanBytes(1536 * 1024), '1.5MB');
    });
  });

  group('throughput', () {
    test('reports bytes per second', () {
      expect(AppLog.throughput(1000, 100), '10000B/s');
    });

    test('does not divide by zero', () {
      expect(AppLog.throughput(1000, 0), 'n/a');
    });
  });

  group('progress', () {
    test('emits once per ten percent step', () {
      expect(AppLog.progress('transfer', 'upload', 100, 1000), isTrue);
      expect(AppLog.progress('transfer', 'upload', 150, 1000), isFalse);
      expect(AppLog.progress('transfer', 'upload', 200, 1000), isTrue);
    });

    test('emits the final step and restarts afterwards', () {
      expect(AppLog.progress('transfer', 'upload', 1000, 1000), isTrue);
      expect(AppLog.progress('transfer', 'upload', 10, 1000), isTrue);
    });

    test('ignores a zero total', () {
      expect(AppLog.progress('transfer', 'upload', 0, 0), isFalse);
    });
  });

  group('atMostEvery', () {
    test('allows the first call and rejects an immediate repeat', () {
      expect(AppLog.atMostEvery('retry', const Duration(seconds: 1)), isTrue);
      expect(AppLog.atMostEvery('retry', const Duration(seconds: 1)), isFalse);
    });

    test('tracks keys independently', () {
      expect(AppLog.atMostEvery('a', const Duration(seconds: 1)), isTrue);
      expect(AppLog.atMostEvery('b', const Duration(seconds: 1)), isTrue);
    });
  });

  group('breadcrumbs', () {
    test('keeps the events that led to a problem, oldest first', () {
      AppLog.i('serial', 'connected COM4');
      AppLog.w('serial', 'no response to the handshake');

      final trail = AppLog.debugBreadcrumbs;
      expect(trail.length, 2);
      expect(trail.first, contains('connected COM4'));
      expect(trail.first, contains('[serial]'));
      expect(trail.last, contains('no response'));
      // The level tag is what makes a trail readable at a glance.
      expect(trail.first, contains(' I '));
      expect(trail.last, contains(' W '));
    });

    test('is bounded so one hot loop cannot grow it without limit', () {
      for (var i = 0; i < 100; i++) {
        AppLog.i('loop', 'tick $i');
      }
      expect(AppLog.debugBreadcrumbs.length, lessThanOrEqualTo(40));
      expect(AppLog.debugBreadcrumbs.last, contains('tick 99'));
    });
  });

  group('formatRecord', () {
    test('carries the trail, the error and the stack', () {
      final record = AppLog.formatRecord(
        AppLogLevel.error,
        'board',
        'upload failed',
        error: 'timeout',
        stack: StackTrace.fromString('#0 send (plugin_run_manager.dart:12)'),
        breadcrumbs: const ['10:00:00.000 I [serial] connected COM4'],
      );

      expect(record, contains('[ERROR] [board] upload failed'));
      expect(record, contains('--- last 1 events ---'));
      expect(record, contains('connected COM4'));
      expect(record, contains('error: timeout'));
      expect(record, contains('plugin_run_manager.dart:12'));
    });

    test('omits sections that have nothing to say', () {
      final record = AppLog.formatRecord(AppLogLevel.warn, 'serial', 'stale');

      expect(record, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
      expect(record, isNot(contains('--- last')));
      expect(record, isNot(contains('error:')));
      expect(record, isNot(contains('stack:')));
    });
  });
}
