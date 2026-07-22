import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

void main() {
  testWidgets('Pyrite RFW IconButton decodes values and emits press events', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final data = rfw.DynamicContent();
    final pageName = rfw.LibraryName(<String>['test']);
    String? eventName;
    formats.DynamicMap? eventArguments;

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
widget root = Column(children: [
  IconButton(
    icon: Icon(icon: 0xe491, fontFamily: "MaterialIcons"),
    selectedIcon: Icon(icon: 0xe047, fontFamily: "MaterialIcons"),
    onPressed: event "pressed" {},
    onLongPress: event "longPressed" {},
    onHover: event "hovered" {},
    tooltip: "Profile",
    iconSize: 28.0,
    visualDensity: {"horizontal": 1.0, "vertical": -1.0},
    padding: [4.0, 8.0],
    alignment: {"x": 1.0, "y": 0.0},
    color: 0xff1565c0,
    disabledColor: 0xff9e9e9e,
    focusColor: 0xff00838f,
    hoverColor: 0xff2e7d32,
    highlightColor: 0xfff9a825,
    splashColor: 0xff6a1b9a,
    splashRadius: 24.0,
    autofocus: true,
    enableFeedback: false,
    constraints: {
      "minWidth": 40.0,
      "maxWidth": 60.0,
      "minHeight": 42.0,
      "maxHeight": 64.0
    },
    isSelected: true
  ),
  IconButton(
    icon: Icon(icon: 0xe491, fontFamily: "MaterialIcons"),
    disabledColor: 0xff9e9e9e
  )
]);
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

    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .toList();
    expect(buttons, hasLength(2));
    expect(buttons.first.iconSize, 28.0);
    expect(
      buttons.first.visualDensity,
      const VisualDensity(horizontal: 1, vertical: -1),
    );
    expect(
      buttons.first.padding,
      const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 8),
    );
    expect(buttons.first.alignment, Alignment.centerRight);
    expect(buttons.first.color, const Color(0xff1565c0));
    expect(buttons.first.disabledColor, const Color(0xff9e9e9e));
    expect(buttons.first.focusColor, const Color(0xff00838f));
    expect(buttons.first.hoverColor, const Color(0xff2e7d32));
    expect(buttons.first.highlightColor, const Color(0xfff9a825));
    expect(buttons.first.splashColor, const Color(0xff6a1b9a));
    expect(buttons.first.splashRadius, 24.0);
    expect(buttons.first.autofocus, isTrue);
    expect(buttons.first.enableFeedback, isFalse);
    expect(
      buttons.first.constraints,
      const BoxConstraints(
        minWidth: 40,
        maxWidth: 60,
        minHeight: 42,
        maxHeight: 64,
      ),
    );
    expect(buttons.first.isSelected, isTrue);
    expect(buttons.first.tooltip, 'Profile');
    expect(buttons.last.onPressed, isNull);

    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons, hasLength(2));
    expect(icons.first.icon?.codePoint, 0xe047);
    expect(icons.first.icon?.fontFamily, 'MaterialIcons');
    expect(icons.last.icon?.codePoint, 0xe491);

    buttons.first.onHover?.call(true);
    expect(eventName, 'hovered');
    expect(eventArguments, <String, Object?>{'value': true});

    buttons.first.onLongPress?.call();
    expect(eventName, 'longPressed');
    expect(eventArguments, <String, Object?>{});

    await tester.tap(find.byType(IconButton).first);
    await tester.pump();

    expect(eventName, 'pressed');
    expect(eventArguments, <String, Object?>{});
  });

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
