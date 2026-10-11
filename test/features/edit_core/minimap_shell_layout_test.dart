import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:pyrite_ide/features/edit_core/editor_minimap.dart';

/// The minimap column must take room *away* from the editor, not sit over it:
/// the shell lays the editor out in the width that remains after
/// [kMinimapWidth], and every wrapped editor gets that column at its own right
/// edge, so coexisting editors never share — or lose — a map.
///
/// The controller is faked: only the handful of members the shell reads are
/// implemented, so the layout is pinned without loading code_forge's Rust
/// runtime, which some environments cannot build.
class _FakeCodeForgeController implements CodeForgeController {
  @override
  double? editorLineHeight;

  @override
  int get lineCount => 0;

  @override
  int get documentVersion => 0;

  @override
  int? get firstVisibleLine => null;

  @override
  int? get visibleLineCount => null;

  @override
  String getLineText(int line) => '';

  @override
  void jumpToLine(int line) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not read by MinimapEditorShell: $invocation');
}

void main() {
  const editorKey = Key('editor');

  Widget shell(
    CodeForgeController controller, {
    required bool enabled,
    required Key editorKey,
  }) {
    return MinimapEditorShell(
      controller: controller,
      enabled: enabled,
      lineWrap: false,
      foreground: Colors.white,
      background: Colors.black,
      editorTheme: const {'root': TextStyle(color: Colors.white)},
      language: resolveEditorLanguage('sample.py').mode,
      baseTextStyle: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
      estimatedLineHeight: 16.8,
      child: SizedBox.expand(key: editorKey),
    );
  }

  Widget host(CodeForgeController controller, Key editorKey) {
    return MaterialApp(
      home: Scaffold(
        body: shell(controller, enabled: true, editorKey: editorKey),
      ),
    );
  }

  // The shell's column, not the same-width SizedBox _MinimapView wraps its
  // canvas in: the column's child is the view widget, the inner one's is a
  // LayoutBuilder.
  final minimapColumn = find.byWidgetPredicate(
    (widget) =>
        widget is SizedBox &&
        widget.width == kMinimapWidth &&
        widget.child is! LayoutBuilder,
  );

  testWidgets(
    'the editor is laid out in the width left of the minimap column',
    (tester) async {
      await tester.pumpWidget(host(_FakeCodeForgeController(), editorKey));
      await tester.pumpAndSettle();

      final shellRect = tester.getRect(find.byType(MinimapEditorShell));
      final editorRect = tester.getRect(find.byKey(editorKey));
      final columnRect = tester.getRect(minimapColumn);

      expect(editorRect.width, shellRect.width - kMinimapWidth);
      // The column sits flush against the editor's right edge and against the
      // shell's right edge, at full height — beside the editor, never over it.
      expect(columnRect.left, editorRect.right);
      expect(columnRect.right, shellRect.right);
      expect(columnRect.height, shellRect.height);
      expect(columnRect.width, kMinimapWidth);
    },
  );

  testWidgets('coexisting editors each carry their own column on their right', (
    tester,
  ) async {
    const firstEditorKey = Key('editor-0');
    const secondEditorKey = Key('editor-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: shell(
                  _FakeCodeForgeController(),
                  enabled: true,
                  editorKey: firstEditorKey,
                ),
              ),
              Expanded(
                child: shell(
                  _FakeCodeForgeController(),
                  enabled: true,
                  editorKey: secondEditorKey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shells = find.byType(MinimapEditorShell);
    expect(shells, findsNWidgets(2));
    expect(minimapColumn, findsNWidgets(2));

    final columns = tester.widgetList<SizedBox>(minimapColumn).toList();
    final editorKeys = [firstEditorKey, secondEditorKey];
    for (var index = 0; index < 2; index++) {
      final shellRect = tester.getRect(shells.at(index));
      final columnRect = tester.getRect(find.byWidget(columns[index]));
      final editorRect = tester.getRect(find.byKey(editorKeys[index]));
      expect(
        editorRect.width,
        shellRect.width - kMinimapWidth,
        reason: 'editor $index keeps its own width',
      );
      expect(
        columnRect.right,
        shellRect.right,
        reason: 'editor $index has its map on its own right edge',
      );
      expect(columnRect.left, editorRect.right);
    }
  });

  testWidgets('a disabled minimap leaves the editor at full width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: shell(
            _FakeCodeForgeController(),
            enabled: false,
            editorKey: editorKey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shellRect = tester.getRect(find.byType(MinimapEditorShell));
    final editorRect = tester.getRect(find.byKey(editorKey));
    expect(editorRect.width, shellRect.width);
    expect(minimapColumn, findsNothing);
  });

  testWidgets('a window too narrow for the map shows none', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: shell(
              _FakeCodeForgeController(),
              enabled: true,
              editorKey: editorKey,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(minimapColumn, findsNothing);
    expect(tester.getSize(find.byKey(editorKey)).width, 500);
  });
}
