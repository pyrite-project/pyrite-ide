/// The terminal's right-click menu: a pure action model plus the popup that
/// renders it.
///
/// The model is separate from the popup so the enable rules — copy only with a
/// selection, everything else always usable — can be asserted without pumping
/// a menu. The popup itself is built from the app-wide menu widgets
/// ([PyriteMenuRow], [PyriteMenuSurface]) rather than inventing a second menu
/// style: icon, label and shortcut hint in the same rows the editor uses.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/shared/pyrite_menu.dart';
import 'package:xterm/xterm.dart';

enum TerminalContextAction { copy, paste, selectAll, clear, search }

/// One row of the terminal menu.
typedef TerminalContextItem = ({
  TerminalContextAction action,
  String label,
  IconData icon,
  String shortcut,
  bool enabled,
});

/// The menu rows, in display order.
///
/// Copy is disabled rather than hidden: a terminal menu whose row count changes
/// under the cursor is a menu that moves its own items, and "copy" being greyed
/// out is the standard way to say "nothing selected yet".
///
/// [actions] subsets the menu for surfaces where an action would do nothing —
/// the output log has nothing to paste into and no search bar, the REPL
/// transcript has no search bar — while keeping the canonical order above.
List<TerminalContextItem> terminalContextMenuItems({
  required bool hasSelection,
  bool isMacOS = false,
  I18nTranslate? translate,
  Set<TerminalContextAction>? actions,
}) {
  final tr = translate ?? fallbackTranslate;
  final modifier = isMacOS ? 'Cmd' : 'Ctrl';
  final items = [
    (
      action: TerminalContextAction.copy,
      label: tr(I18nKey.terminalMenuCopy),
      icon: Icons.copy,
      shortcut: '$modifier+Shift+C',
      enabled: hasSelection,
    ),
    (
      action: TerminalContextAction.paste,
      label: tr(I18nKey.terminalMenuPaste),
      icon: Icons.paste,
      shortcut: '$modifier+V',
      enabled: true,
    ),
    (
      action: TerminalContextAction.selectAll,
      label: tr(I18nKey.terminalMenuSelectAll),
      icon: Icons.select_all,
      shortcut: '$modifier+A',
      enabled: true,
    ),
    (
      action: TerminalContextAction.clear,
      label: tr(I18nKey.terminalMenuClear),
      icon: Icons.cleaning_services_outlined,
      shortcut: '',
      enabled: true,
    ),
    (
      action: TerminalContextAction.search,
      label: tr(I18nKey.terminalMenuSearch),
      icon: Icons.search,
      shortcut: findShortcutLabel(),
      enabled: true,
    ),
  ];
  if (actions == null) return items;
  return [
    for (final item in items)
      if (actions.contains(item.action)) item,
  ];
}

/// Shows the terminal menu at [globalPosition] and reports the pick.
///
/// The menu is driven from `TerminalView.onSecondaryTapUp` rather than from the
/// tree's `PyriteContextMenuWidget` because the terminal already owns its
/// pointer gestures: xterm sends right clicks to the running program when that
/// program asked for mouse reporting, and a second gesture recognizer wrapping
/// the view would compete with xterm's and break that path. Driving the menu
/// from the pointer callback keeps exactly one owner of the pointer stream.
///
/// It is rendered by [showPyriteMenu] rather than `showMenu` so it opens
/// instantly and matches the editor's menu surface — the same rounded panel,
/// the same row metrics. See `pyrite_menu.dart`.
Future<TerminalContextAction?> showTerminalContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required bool hasSelection,
  Set<TerminalContextAction>? actions,
}) {
  final items = terminalContextMenuItems(
    hasSelection: hasSelection,
    isMacOS: usesCommandShortcut,
    translate: (key, [replacements = const {}]) =>
        translateInContextWithReplacements(context, key, replacements),
    actions: actions,
  );

  return showPyriteMenu<TerminalContextAction>(
    context,
    globalPosition: globalPosition,
    entries: [
      for (final item in items)
        PyriteMenuEntry(
          value: item.action,
          label: item.label,
          icon: item.icon,
          shortcut: item.shortcut,
          enabled: item.enabled,
        ),
    ],
  );
}

/// Applies a picked menu action to an xterm [terminal] and its [controller].
///
/// Search is deliberately absent: only a surface that owns a search bar can
/// open one, so surfaces that put `search` in their menu handle that pick
/// themselves before deferring the rest here.
Future<void> applyTerminalContextAction(
  TerminalContextAction action, {
  required Terminal terminal,
  required TerminalController controller,
}) async {
  switch (action) {
    case TerminalContextAction.copy:
      final selection = controller.selection;
      if (selection == null) return;
      final text = terminal.buffer.getText(selection);
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
    case TerminalContextAction.paste:
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      // `paste` honours bracketed paste mode, which is how a shell protects a
      // pasted multi-line block from executing immediately.
      terminal.paste(text);
      controller.clearSelection();
    case TerminalContextAction.selectAll:
      final buffer = terminal.buffer;
      controller.setSelection(
        buffer.createAnchor(0, 0),
        buffer.createAnchor(terminal.viewWidth, buffer.height - 1),
        mode: SelectionMode.line,
      );
    case TerminalContextAction.clear:
      // Clears the screen and scrollback. The program is not signalled: an
      // interactive shell redraws its prompt the next time it writes, while
      // clearing the buffer directly also works for a REPL that is not reading
      // stdin at this instant.
      terminal.clear();
      controller.clearSelection();
    case TerminalContextAction.search:
      break;
  }
}
