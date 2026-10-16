import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/function_page.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

/// Opens the panel position menu on a secondary tap of a console tab.
///
/// This is VS Code's "Panel Position" entry, reached the same way: from the
/// panel's own context menu rather than from a button. There is no drag
/// controller anywhere — moving tabs is a drag, moving the panel is a command.
void showConsoleDockMenu(
  BuildContext context,
  WidgetRef ref,
  TapDownDetails details,
) {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return;
  final position = RelativeRect.fromLTRB(
    details.globalPosition.dx,
    details.globalPosition.dy,
    overlay.size.width - details.globalPosition.dx,
    overlay.size.height - details.globalPosition.dy,
  );
  showMenu<ConsoleDockSide>(
    context: context,
    position: position,
    items: [
      for (final side in ConsoleDockSide.values)
        PopupMenuItem<ConsoleDockSide>(
          value: side,
          child: Row(
            children: [
              Icon(side.icon, size: 16),
              const SizedBox(width: 8),
              UseText(side.labelKey),
              if (side == ref.read(consoleDockSideProvider)) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
    ],
  ).then((side) {
    if (side == null) return;
    ref.read(consoleDockSideProvider.notifier).state = side;
  });
}
