import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/pyrite_material_widgets.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

void main() {
  testWidgets('Pyrite RFW TextField edits text and emits value events', (
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
widget root = TextField(
  initialValue: "old",
  decoration: {"labelText": "Name", "hintText": "Type here"},
  textInputAction: "done",
  onChanged: event "changed" {},
  onSubmitted: event "submitted" {}
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

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'old',
    );
    expect(find.text('Name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'hello',
    );
    expect(eventName, 'changed');
    expect(eventArguments, <String, Object?>{'value': 'hello'});

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(eventName, 'submitted');
    expect(eventArguments, <String, Object?>{'value': 'hello'});
  });
}
