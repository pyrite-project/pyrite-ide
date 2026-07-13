import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

void main() {
  testWidgets('RFW Icon decodes flattened Material IconData payload', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final data = rfw.DynamicContent();
    final pageName = rfw.LibraryName(<String>['icon_test']);

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
widget root = Icon(icon: 0xe491, fontFamily: "MaterialIcons");
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: rfw.RemoteWidget(
          runtime: runtime,
          data: data,
          widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon)).icon;
    expect(icon?.codePoint, 0xe491);
    expect(icon?.fontFamily, 'MaterialIcons');
  });
}
