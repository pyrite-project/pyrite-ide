/// The floating find bar shown over a desktop terminal.
///
/// Split from the terminal surface so the surface stays about wiring (focus,
/// buffer snapshots, highlight ownership) and this file stays about one piece
/// of layout. The bar deliberately owns no state: the query text lives in the
/// controller the surface keeps alive, and the match/counter state arrives as
/// [TerminalSearchState].
library;

import 'package:flutter/material.dart';

import 'package:pyrite_ide/features/terminal/terminal_search.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

class TerminalSearchBar extends StatelessWidget {
  const TerminalSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.state,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleCase,
    required this.onClose,
  });

  final TextEditingController controller;

  /// The surface attaches `onKeyEvent` to this node so Enter/Shift+Enter and
  /// Escape reach the bar before the text field's own handling does.
  final FocusNode focusNode;

  final TerminalSearchState state;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleCase;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // "无结果" is shown instead of "0/0": the latter reads like an off-by-one
    // bug even though it is correct.
    final counter = state.isActive && !state.hasMatches
        ? translateInContext(context, I18nKey.terminalSearchNoResults)
        : state.counterLabelFor(
            (key, [replacements = const {}]) =>
                translateInContextWithReplacements(context, key, replacements),
          );

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: translateInContext(
                    context,
                    I18nKey.terminalSearchHint,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.bodySmall,
                onChanged: onChanged,
              ),
            ),
            if (counter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  counter,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            _barButton(
              context,
              icon: Icons.text_fields,
              tooltip: translateInContext(
                context,
                I18nKey.terminalSearchCaseSensitive,
              ),
              selected: state.caseSensitive,
              onPressed: onToggleCase,
            ),
            _barButton(
              context,
              icon: Icons.keyboard_arrow_up,
              tooltip: translateInContext(
                context,
                I18nKey.terminalSearchPrevious,
              ),
              onPressed: state.hasMatches ? onPrevious : null,
            ),
            _barButton(
              context,
              icon: Icons.keyboard_arrow_down,
              tooltip: translateInContext(context, I18nKey.terminalSearchNext),
              onPressed: state.hasMatches ? onNext : null,
            ),
            _barButton(
              context,
              icon: Icons.close,
              tooltip: translateInContext(context, I18nKey.terminalSearchClose),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _barButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            )
          : null,
    );
  }
}
