import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_canvas.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Map<String, dynamic> _rect(
  String id,
  double x,
  double y,
  double width,
  double height,
) => {'op': 'rect', 'id': id, 'x': x, 'y': y, 'w': width, 'h': height};

void main() {
  testWidgets('hit testing follows transforms and clip bounds', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PluginCanvas(
          componentId: 'surface',
          width: 200,
          height: 120,
          ops: [
            {'op': 'save'},
            {'op': 'translate', 'dx': 10, 'dy': 0},
            {'op': 'clip', 'shape': 'rect', 'x': 0, 'y': 0, 'w': 10, 'h': 10},
            _rect('clipped', 0, 0, 30, 20),
            {'op': 'restore'},
            {
              'op': 'group',
              'transform': [1, 0, 0, 1, 40, 0],
              'clip': {
                'op': 'clip',
                'shape': 'rect',
                'x': 0,
                'y': 0,
                'w': 10,
                'h': 10,
              },
              'ops': [_rect('grouped', 0, 0, 20, 20)],
            },
          ],
        ),
      ),
    );

    final state = tester.state<PluginCanvasState>(find.byType(PluginCanvas));
    expect(state.hitTest(15, 5)?['elementId'], 'clipped');
    expect(state.hitTest(25, 5), isNull);
    expect(state.hitTest(45, 5)?['elementId'], 'grouped');
    expect(state.hitTest(55, 5), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid restore is contained and unbounded height gets a fallback',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: Column(
              children: [
                PluginCanvas(
                  componentId: 'surface',
                  ops: [
                    {'op': 'restore'},
                    {'op': 'translate', 'dx': 10, 'dy': 10},
                    _rect('box', 0, 0, 20, 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(PluginCanvas)).height, 200);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tap payload uses content coordinates and the topmost element', (
    tester,
  ) async {
    final events = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      _wrap(
        Align(
          alignment: Alignment.topLeft,
          child: PluginCanvas(
            componentId: 'surface',
            width: 100,
            height: 100,
            interactive: true,
            viewport: const {'scale': 2, 'offsetX': 5},
            ops: [_rect('target', 10, 10, 20, 20)],
            onTap: events.add,
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(PluginCanvas));
    await tester.tapAt(origin + const Offset(40, 40));
    expect(events, hasLength(1));
    expect(events.single['elementId'], 'target');
    expect(events.single['x'], 15);
    expect(events.single['y'], 20);
  });

  testWidgets('a throttled drag update never arrives after end', (
    tester,
  ) async {
    final phases = <String>[];
    await tester.pumpWidget(
      _wrap(
        Align(
          alignment: Alignment.topLeft,
          child: PluginCanvas(
            componentId: 'surface',
            width: 200,
            height: 100,
            onDrag: (payload) => phases.add(payload['phase'] as String),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(PluginCanvas));
    final gesture = await tester.startGesture(origin + const Offset(10, 10));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.moveBy(const Offset(10, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    expect(phases.first, 'start');
    expect(phases.last, 'end');
    expect(phases.where((phase) => phase == 'end'), hasLength(1));
  });
}
