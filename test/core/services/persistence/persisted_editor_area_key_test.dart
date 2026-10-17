import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/file_tab_title.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/persistence/persistence_manager.dart';
import 'package:tabbed_view/tabbed_view.dart';

/// The fingerprint the auto-save compares decides whether a change in the
/// editor area is worth writing the session for.
void main() {
  TabData fileTab(String path) => TabData(
    text: path,
    value: TabDataValue(type: 'file', filePath: path),
  );

  test('moves with what is persisted, and only with that', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final primary = container.read(tabbedViewControllerProvider);
    final a = fileTab('/proj/client/a.py');
    final b = fileTab('/proj/server/a.py');
    primary
      ..addTab(a)
      ..addTab(b);
    var key = persistedEditorAreaKey(container);

    // A title refresh changes no persisted field.
    refreshFileTabTitles(allEditorTabs(container));
    expect(persistedEditorAreaKey(container), key);

    // Selecting another tab does: the selection is restored on restart.
    primary.selectedIndex = 1;
    expect(persistedEditorAreaKey(container), isNot(key));
    key = persistedEditorAreaKey(container);

    // So does splitting the area.
    container
        .read(editorLayoutProvider.notifier)
        .splitGroup(
          from: primary,
          target: primary,
          tab: b,
          where: EditorSplit.right,
        );
    expect(persistedEditorAreaKey(container), isNot(key));
    key = persistedEditorAreaKey(container);

    // And a tab turning modified, since its buffer is then written too.
    editorTabValueOf(a)!.isSaved = false;
    expect(persistedEditorAreaKey(container), isNot(key));
  });
}
