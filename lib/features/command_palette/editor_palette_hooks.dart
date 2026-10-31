import 'package:pyrite_ide/core/services/editor/editor_layout_commands.dart';
import 'package:pyrite_ide/features/command_palette/builtin_entries.dart';

/// The editor-group commands the palette exposes, wired to the real editor.
///
/// The palette module deliberately does not import the editor's UI helpers:
/// tests and previews pass an empty hook set, while the running app supplies
/// this one. Keeping the wiring in one function makes the menu, shortcut and
/// palette entry paths use exactly the same commands.
CommandPaletteHooks editorPaletteHooks() => CommandPaletteHooks(
  reopenLastClosedTab: (context, ref) async {
    await reopenClosedEditorTab(context, ref);
  },
  closeEditorGroup: (context, ref) async {
    await closeActiveEditorGroup(context, ref);
  },
  resetEditorLayout: (context, ref) async {
    resetEditorLayout(ref);
  },
);
