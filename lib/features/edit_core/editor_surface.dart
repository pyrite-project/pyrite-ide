import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/features/edit_core/editor_outline_panel.dart';

/// Whether the editor's outline column is showing.
///
/// Kept in a provider rather than in the editor's widget state: the toggle
/// lives in the toolbar and the panel lives in the workspace, and they are
/// rebuilt independently as the layout changes.
final StateProvider<bool> editorOutlineVisible = StateProvider<bool>(
  (ref) => false,
);

/// The editor page with an optional outline column beside the tabbed view.
///
/// The outline answers a question the tab strip cannot: where in this file is
/// the thing I want. It is opt-in because on a narrow window the column costs
/// more width than the navigation is worth.
class EditorSurface extends ConsumerWidget {
  const EditorSurface({super.key, required this.child});

  /// The tabbed editor area.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(editorOutlineVisible);
    if (!visible) return child;

    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    final width = isCompact ? 220.0 : 260.0;

    return Row(
      children: [
        Expanded(child: child),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        SizedBox(
          width: width,
          child: Column(
            children: [
              _OutlineHeaderBar(
                onClose: () =>
                    ref.read(editorOutlineVisible.notifier).state = false,
              ),
              const Divider(height: 1),
              const Expanded(child: EditorOutlinePanel()),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutlineHeaderBar extends ConsumerWidget {
  const _OutlineHeaderBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              translateForWidget(ref, I18nKey.editorOutlineTitle),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: translateForWidget(ref, I18nKey.editorOutlineTitle),
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// Toolbar button that shows or hides the outline column.
class EditorOutlineToggle extends ConsumerWidget {
  const EditorOutlineToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(editorOutlineVisible);
    return IconButton(
      tooltip: translateForWidget(ref, I18nKey.editorOutlineTitle),
      isSelected: visible,
      icon: const Icon(Icons.account_tree_outlined),
      selectedIcon: const Icon(Icons.account_tree),
      onPressed: () => ref.read(editorOutlineVisible.notifier).state = !visible,
    );
  }
}
