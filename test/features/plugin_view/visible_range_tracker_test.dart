import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_data_table.dart';
import 'package:pyrite_ide/features/plugin_view/data/plugin_virtual_list.dart';
import 'package:pyrite_ide/features/plugin_view/data/visible_range_tracker.dart';

Widget _wrap(Widget child, {double height = 400, double width = 600}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(height: height, width: width, child: child),
      ),
    );

void main() {
  group('VisibleRangeTracker failure recovery', () {
    test(
      'a chunk is requested again once the retry window has passed',
      () async {
        final requests = <({int start, int count})>[];
        final tracker = VisibleRangeTracker(
          onRequest: (start, count) =>
              requests.add((start: start, count: count)),
          debounce: const Duration(milliseconds: 20),
          chunkSize: 100,
          retryAfter: const Duration(milliseconds: 30),
        );
        addTearDown(tracker.dispose);

        tracker.noteMissing(0, 50);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(requests, hasLength(1));
        expect(tracker.isChunkRequested(0), isTrue);

        // No rows arrived (a stopped transport or a plugin-side error), and the
        // rows are still missing on the next rebuild.
        tracker.noteMissing(0, 50);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(requests, hasLength(2));
        expect(requests.last.start, 0);
        expect(requests.last.count, 100);
      },
    );

    test('a chunk inside the retry window is not requested twice', () async {
      final requests = <({int start, int count})>[];
      final tracker = VisibleRangeTracker(
        onRequest: (start, count) => requests.add((start: start, count: count)),
        debounce: const Duration(milliseconds: 20),
        chunkSize: 100,
        retryAfter: const Duration(seconds: 5),
      );
      addTearDown(tracker.dispose);

      tracker.noteMissing(0, 50);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      tracker.noteMissing(10, 60);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(requests, hasLength(1));
    });

    test('reset makes already-requested chunks eligible again', () async {
      final requests = <({int start, int count})>[];
      final tracker = VisibleRangeTracker(
        onRequest: (start, count) => requests.add((start: start, count: count)),
        debounce: const Duration(milliseconds: 20),
        chunkSize: 100,
        retryAfter: const Duration(seconds: 5),
      );
      addTearDown(tracker.dispose);

      tracker.noteMissing(200, 250);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(requests, hasLength(1));

      tracker.reset();
      expect(tracker.isChunkRequested(200), isFalse);

      tracker.noteMissing(200, 250);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(requests, hasLength(2));
      expect(requests.last.start, 200);
    });
  });

  group('list windows retry ranges after a plugin snapshot', () {
    testWidgets(
      'PluginVirtualList re-requests a missing window on a new revision',
      (tester) async {
        final requests = <int>[];
        Widget list(int revision) => _wrap(
          PluginVirtualList(
            items: const <int, Map<String, dynamic>>{},
            itemCount: 5000,
            dataRevision: revision,
            onRequestRange: (start, count) => requests.add(start),
          ),
        );

        await tester.pumpWidget(list(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0]);

        // A rebuild from the same snapshot must not duplicate the request.
        await tester.pumpWidget(list(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0]);

        // A new snapshot still has no rows, so the range must be retried.
        await tester.pumpWidget(list(2));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0, 0]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PluginDataTable re-requests a missing window on a new revision',
      (tester) async {
        final requests = <int>[];
        Widget table(int revision) => _wrap(
          PluginDataTable(
            columns: const [PluginColumn(id: 'name', label: 'Name')],
            rows: const <int, Map<String, dynamic>>{},
            rowCount: 5000,
            dataRevision: revision,
            onRequestRange: (start, count) => requests.add(start),
          ),
        );

        await tester.pumpWidget(table(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0]);

        await tester.pumpWidget(table(1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0]);

        await tester.pumpWidget(table(2));
        await tester.pump(const Duration(milliseconds: 200));
        expect(requests, [0, 0]);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
