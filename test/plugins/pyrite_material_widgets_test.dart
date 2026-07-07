import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart' as markdown_widget;
import 'package:pyrite_ide/pages/plugins/pyrite_material_widgets.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;

bool _spanTreeHasFontFamily(InlineSpan span, String fontFamily) {
  if (span.style?.fontFamily == fontFamily) {
    return true;
  }
  if (span is TextSpan) {
    return span.children?.any(
          (InlineSpan child) => _spanTreeHasFontFamily(child, fontFamily),
        ) ??
        false;
  }
  return false;
}

bool _spanTreeTextUsesFontFamily(InlineSpan span, String fontFamily) {
  bool sawText = false;

  bool visit(InlineSpan current, TextStyle? inheritedStyle) {
    final effectiveStyle =
        inheritedStyle?.merge(current.style) ?? current.style;
    if (current is! TextSpan) {
      return true;
    }

    final text = current.text;
    if (text != null && text.isNotEmpty) {
      sawText = true;
      if (effectiveStyle?.fontFamily != fontFamily) {
        return false;
      }
    }

    final children = current.children;
    if (children == null) {
      return true;
    }
    return children.every((InlineSpan child) => visit(child, effectiveStyle));
  }

  return visit(span, null) && sawText;
}

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

  testWidgets('Pyrite RFW Markdown renders markdown and emits link events', (
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
      formats.parseLibraryFile(r'''
import core.material;
widget root = MarkdownBlock(
  data: "# Title\n\n[docs](https://example.com)\n\n`inlineCode`\n\n```dart\nprint(1);\n```",
  selectable: false,
  codeBlockTextStyle: {
    "fontFamily": "Menlo",
    "fontFamilyFallback": ["SF Mono", "Monaco"],
    "fontSize": 13.0
  },
  codeBlockStyleNotMatched: {"color": 0xffe5e7eb},
  codeBlockTheme: "dark",
  inlineCodeTextStyle: {
    "fontFamily": "Menlo",
    "backgroundColor": 0xff374151
  },
  onTapLink: event "linkTapped" {}
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

    expect(find.byType(markdown_widget.MarkdownBlock), findsOneWidget);
    final markdownBlock = tester.widget<markdown_widget.MarkdownBlock>(
      find.byType(markdown_widget.MarkdownBlock),
    );
    final codeTheme = markdownBlock.config?.pre.theme;
    expect(
      codeTheme?['comment']?.color,
      markdown_widget.PreConfig.darkConfig.theme['comment']?.color,
    );
    expect(codeTheme?['comment']?.fontFamily, 'Menlo');
    expect(
      markdownBlock.config?.pre.styleNotMatched?.color,
      const Color(0xffe5e7eb),
    );
    expect(
      markdownBlock.config?.code.style.backgroundColor,
      const Color(0xff374151),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.textContaining('docs'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('inlineCode') &&
            _spanTreeHasFontFamily(widget.text, 'Menlo'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('print(1);') &&
            _spanTreeTextUsesFontFamily(widget.text, 'Menlo'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('docs'));
    await tester.pump();

    expect(eventName, 'linkTapped');
    expect(eventArguments, <String, Object?>{'url': 'https://example.com'});
  });

  testWidgets('Pyrite RFW Markdown does not set code fonts implicitly', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final data = rfw.DynamicContent();
    final pageName = rfw.LibraryName(<String>['test']);

    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile(r'''
import core.material;
widget root = MarkdownBlock(
  data: "`inlineCode`\n\n```dart\nprint(1);\n```",
  selectable: false
);
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

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('inlineCode') &&
            _spanTreeHasFontFamily(widget.text, 'Menlo'),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('print(1);') &&
            _spanTreeHasFontFamily(widget.text, 'Menlo'),
      ),
      findsNothing,
    );
  });
}
