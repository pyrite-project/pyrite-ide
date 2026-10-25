import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/outline_tab.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/shared/tabbed_view/tabbed_view.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

/// The editor page with the optional outline tab group beside the tabbed
/// view.
///
/// The outline is an ordinary editor tab — draggable, closable, several can
/// exist — that is born into its own column docked at the far right. The
/// column is outline-only: a file tab dropped there would leave the editor
/// controller whose state every consumer (document host, persistence, save
/// actions) reads, so its [TabbedView.canDrop] rejects anything but outline
/// tabs, while the editor bar accepts them like any other tab.
class EditorSurface extends ConsumerStatefulWidget {
  const EditorSurface({super.key, required this.child});

  /// The tabbed editor area.
  final Widget child;

  @override
  ConsumerState<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends ConsumerState<EditorSurface> {
  /// The live controllers a change-listener is attached to.
  ///
  /// The tabbed_view package mutates its controller in place — native drag
  /// drops, tab reorders and tab closes all bypass the copy-on-write
  /// providers — so these listeners are what carry those mutations back into
  /// provider state.
  TabbedViewController? _listenedMain;
  TabbedViewController? _listenedColumn;

  /// Last-seen tab list for the editor bar, so a controller notification only
  /// republishes when membership or order actually changed. Dirty-dot flips
  /// and selection changes notify the same controller and already have their
  /// own paths.
  List<TabData>? _lastMainTabs;

  @override
  void dispose() {
    _listenedMain?.removeListener(_onMainChanged);
    _listenedColumn?.removeListener(_onColumnChanged);
    super.dispose();
  }

  void _onMainChanged() {
    final controller = _listenedMain;
    if (controller == null || _sameTabs(controller.tabs, _lastMainTabs)) {
      return;
    }
    _lastMainTabs = List<TabData>.from(controller.tabs);
    ref.read(tabbedViewControllerProvider.notifier).republishTabs();
  }

  void _onColumnChanged() {
    final controller = _listenedColumn;
    if (controller == null) return;
    if (controller.tabs.isEmpty) {
      // The last outline was dragged (or closed) out of the column.
      ref.read(editorOutlineColumnProvider.notifier).state = null;
    }
  }

  bool _sameTabs(Iterable<TabData> tabs, List<TabData>? snapshot) {
    if (snapshot == null || tabs.length != snapshot.length) return false;
    var index = 0;
    for (final tab in tabs) {
      if (!identical(tab, snapshot[index])) return false;
      index++;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final main = ref.watch(tabbedViewControllerProvider);
    if (!identical(_listenedMain, main)) {
      _listenedMain?.removeListener(_onMainChanged);
      _listenedMain = main;
      _lastMainTabs = List<TabData>.from(main.tabs);
      main.addListener(_onMainChanged);
    }
    final column = ref.watch(editorOutlineColumnProvider);
    if (!identical(_listenedColumn, column)) {
      _listenedColumn?.removeListener(_onColumnChanged);
      _listenedColumn = column;
      column?.addListener(_onColumnChanged);
    }

    if (column == null || column.tabs.isEmpty) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    final width = isCompact ? 220.0 : 260.0;

    return Row(
      children: [
        Expanded(child: widget.child),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        SizedBox(
          width: width,
          child: TabbedView(
            controller: column,
            canDrop: (source, _) => source.tabData.value is OutlineTabValue,
          ),
        ),
      ],
    );
  }
}

/// Toolbar button that opens the outline.
///
/// Every press births another outline tab in the rightmost column; the
/// selected state mirrors whether any outline tab exists, wherever the user
/// has dragged them.
class EditorOutlineToggle extends ConsumerWidget {
  const EditorOutlineToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final main = ref.watch(tabbedViewControllerProvider);
    final column = ref.watch(editorOutlineColumnProvider);
    final hasOutline =
        main.tabs.any(isOutlineTab) || (column != null && column.tabs.any(isOutlineTab));
    return IconButton(
      tooltip: translateForWidget(ref, I18nKey.editorOutlineTitle),
      isSelected: hasOutline,
      icon: const Icon(Icons.account_tree_outlined),
      selectedIcon: const Icon(Icons.account_tree),
      onPressed: () => openOutlineTab(context, ref),
    );
  }
}
