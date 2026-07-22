import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

void main() {
  testWidgets('Pyrite RFW RadioGroup decodes item labels and values', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final data = rfw.DynamicContent();
    final pageName = rfw.LibraryName(<String>['test']);
    String? eventName;
    formats.DynamicMap? eventArguments;

    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.material;
widget root = RadioGroup(
  groupValue: "beta",
  items: [
    {"value": "alpha", "label": "Alpha"},
    {"value": "beta", "label": "Beta"}
  ],
  onChanged: event "changed" {}
);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: rfw.RemoteWidget(
          runtime: runtime,
          data: data,
          widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
          onEvent: (String name, formats.DynamicMap arguments) {
            eventName = name;
            eventArguments = arguments;
          },
        ),
      ),
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(
      tester
          .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>))
          .map((tile) => tile.value),
      <String>['alpha', 'beta'],
    );

    await tester.tap(find.text('Alpha'));
    await tester.pump();

    expect(eventName, 'changed');
    expect(eventArguments, <String, Object?>{'value': 'alpha'});
  });
}
