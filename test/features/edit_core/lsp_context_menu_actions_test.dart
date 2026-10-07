import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/lsp_context_menu_actions.dart';

void main() {
  Set<EditorLspMenuAction> actions({
    bool hasLanguageServer = true,
    bool goToDefinition = true,
    bool rename = true,
  }) => lspContextMenuActions(
    hasLanguageServer: hasLanguageServer,
    goToDefinition: goToDefinition,
    rename: rename,
  );

  test('no language server means no LSP entries at all', () {
    expect(
      actions(hasLanguageServer: false),
      isEmpty,
      reason: 'there is nothing for these entries to ask without a server',
    );
  });

  test('both switches on offers every LSP entry', () {
    expect(actions(), {
      EditorLspMenuAction.goToDefinition,
      EditorLspMenuAction.goToImplementation,
      EditorLspMenuAction.rename,
      EditorLspMenuAction.findReferences,
    });
  });

  test('turning off go-to-definition drops definition and implementation', () {
    final offered = actions(goToDefinition: false);

    expect(offered.contains(EditorLspMenuAction.goToDefinition), isFalse);
    expect(offered.contains(EditorLspMenuAction.goToImplementation), isFalse);
    expect(offered.contains(EditorLspMenuAction.rename), isTrue);
    expect(offered.contains(EditorLspMenuAction.findReferences), isTrue);
  });

  test('turning off rename drops only rename', () {
    final offered = actions(rename: false);

    expect(offered.contains(EditorLspMenuAction.rename), isFalse);
    expect(offered.contains(EditorLspMenuAction.goToDefinition), isTrue);
    expect(offered.contains(EditorLspMenuAction.goToImplementation), isTrue);
    expect(offered.contains(EditorLspMenuAction.findReferences), isTrue);
  });

  test('turning both off still leaves find references', () {
    expect(actions(goToDefinition: false, rename: false), {
      EditorLspMenuAction.findReferences,
    });
  });

  test('flipping a switch changes the menu, in both directions', () {
    final before = actions();
    final after = actions(goToDefinition: false);

    expect(before, isNot(after));
    expect(actions(goToDefinition: true), before);
  });
}
