/// The terminal's right-click menu: a pure action model plus the popup that
/// renders it.
///
/// The model is separate from the popup so the enable rules — copy only with a
/// selection, everything else always usable — can be asserted without pumping
/// a menu. The popup itself intentionally mirrors the editor's
/// `_EditorContextMenu` row (icon, label, shortcut hint) rather than inventing a
/// second menu style.
library;

import 'package:flutter/material.dart';

import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';

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
List<TerminalContextItem> terminalContextMenuItems({
  required bool hasSelection,
  bool isMacOS = false,
}) {
  final modifier = isMacOS ? 'Cmd' : 'Ctrl';
  return [
    (
      action: TerminalContextAction.copy,
      label: I18nKey.terminalMenuCopy.fallback,
      icon: Icons.copy,
      shortcut: '$modifier+Shift+C',
      enabled: hasSelection,
    ),
    (
      action: TerminalContextAction.paste,
      label: I18nKey.terminalMenuPaste.fallback,
      icon: Icons.paste,
      shortcut: '$modifier+V',
      enabled: true,
    ),
    (
      action: TerminalContextAction.selectAll,
      label: I18nKey.terminalMenuSelectAll.fallback,
      icon: Icons.select_all,
      shortcut: '$modifier+A',
      enabled: true,
    ),
    (
      action: TerminalContextAction.clear,
      label: I18nKey.terminalMenuClear.fallback,
      icon: Icons.cleaning_services_outlined,
      shortcut: '',
      enabled: true,
    ),
    (
      action: TerminalContextAction.search,
      label: I18nKey.terminalMenuSearch.fallback,
      icon: Icons.search,
      shortcut: findShortcutLabel(),
      enabled: true,
    ),
  ];
}

/// Shows the terminal menu at [globalPosition] and reports the pick.
///
/// `showMenu` is used instead of the tree's `PyriteContextMenuWidget` because
/// the terminal already owns its pointer gestures: xterm sends right clicks to
/// the running program when that program asked for mouse reporting, and a
/// second gesture recognizer wrapping the view would compete with xterm's and
/// break that path. Driving the menu from `TerminalView.onSecondaryTapUp` keeps
/// exactly one owner of the pointer stream.
Future<TerminalContextAction?> showTerminalContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required bool hasSelection,
}) {
  // The overlay's coordinate space is the app window; RelativeRect needs the
  // menu anchored at the pointer, with the same point as both ends of the
  // rectangle so it grows down-right from the click.
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );

  final items = terminalContextMenuItems(
    hasSelection: hasSelection,
    isMacOS: usesCommandShortcut,
  );

  return showMenu<TerminalContextAction>(
    context: context,
    position: position,
    items: [
      for (final item in items)
        PopupMenuItem<TerminalContextAction>(
          value: item.action,
          enabled: item.enabled,
          height: 36,
          child: _TerminalContextMenuRow(item: item),
        ),
    ],
  );
}

class _TerminalContextMenuRow extends StatelessWidget {
  const _TerminalContextMenuRow({required this.item});

  final TerminalContextItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = item.enabled
        ? scheme.onSurface
        : scheme.onSurface.withAlpha(97);
    return Row(
      children: [
        Icon(item.icon, size: 16, color: foreground),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground),
          ),
        ),
        if (item.shortcut.isNotEmpty) ...[
          const SizedBox(width: 16),
          Text(
            item.shortcut,
            style: TextStyle(
              fontSize: 11,
              color: item.enabled
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface.withAlpha(97),
            ),
          ),
        ],
      ],
    );
  }
}
