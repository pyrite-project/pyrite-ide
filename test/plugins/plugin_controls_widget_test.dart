import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

void main() {
  testWidgets('Pyrite RFW FilledButton renders style and emits press events', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final data = rfw.DynamicContent();
    final pageName = rfw.LibraryName(<String>['test']);
    String? eventName;

    runtime.update(
      rfw.LibraryName(<String>['core', 'widgets']),
      rfw.createCoreWidgets(),
    );
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.widgets;
import core.material;
widget root = FilledButton(
  style: {
    "foregroundColor": 0xffffffff,
    "backgroundColor": 0xff1565c0,
    "padding": [20.0, 10.0],
    "minimumSize": [120.0, 40.0]
  },
  onPressed: event "pressed" {},
  child: Text(text: "Run")
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
          },
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xff1565c0),
    );
    expect(
      button.style?.minimumSize?.resolve(<WidgetState>{}),
      const Size(120, 40),
    );

    await tester.tap(find.text('Run'));
    await tester.pump();

    expect(eventName, 'pressed');
  });

  testWidgets('Pyrite RFW Slider decodes values and emits value events', (
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
widget root = Slider(
  value: 0.25,
  secondaryTrackValue: 0.5,
  min: 0.0,
  max: 1.0,
  divisions: 4,
  label: "Level",
  activeColor: 0xff2e7d32,
  onChanged: event "changed" {},
  onChangeEnd: event "ended" {}
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

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0.25);
    expect(slider.secondaryTrackValue, 0.5);
    expect(slider.divisions, 4);
    expect(slider.label, 'Level');
    expect(slider.activeColor, const Color(0xff2e7d32));

    slider.onChanged?.call(0.75);
    expect(eventName, 'changed');
    expect(eventArguments, <String, Object?>{'value': 0.75});

    slider.onChangeEnd?.call(1.0);
    expect(eventName, 'ended');
    expect(eventArguments, <String, Object?>{'value': 1.0});
  });
}
