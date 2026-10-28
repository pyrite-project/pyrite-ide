import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/file/local_tree.dart';
import 'package:pyrite_ide/core/services/search/search_provider.dart';
import 'package:pyrite_ide/core/services/search/search_service.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:pyrite_ide/pages/search/search_results_view.dart';
import 'package:responsive_framework/responsive_framework.dart';

String _tr(
  WidgetRef ref,
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  var value = translateForWidget(ref, key);
  for (final entry in replacements.entries) {
    value = value.replaceAll('{${entry.key}}', entry.value);
  }
  return value;
}

/// Standalone "global search / cross-file replace" page, reachable from the
/// left navigation rail. Mirrors the project tree's local scope (the currently
/// opened project directory) and reuses the git-ignore filter.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  Future<void> _revealFlat(FlatSearchMatch flat) async {
    // Capture before the await so we never touch the context across the gap.
    final isDesktop = ResponsiveBreakpoints.of(context).isDesktop;
    final character = flat.match.ranges[flat.rangeIndex].$1;
    await revealLspLocation(
      context,
      ref,
      flat.filePath,
      flat.match.lineIndex,
      character,
    );
    // On desktop the editor pane is always visible, so the jump is enough. On
    // mobile/tablet the editor is its own route, so switch to it.
    if (!isDesktop && mounted) {
      context.go('/editor');
    }
  }

  /// A result row was tapped: point the current-match cursor at that
  /// occurrence, then open it.
  void _openFromView(String filePath, int lineIndex, int rangeIndex) {
    final state = ref.read(searchRunnerProvider);
    final flats = state.flatMatches;
    for (var i = 0; i < flats.length; i++) {
      final flat = flats[i];
      if (flat.filePath == filePath &&
          flat.match.lineIndex == lineIndex &&
          flat.rangeIndex == rangeIndex) {
        ref.read(searchRunnerProvider.notifier).setCurrent(i);
        _revealFlat(flat);
        return;
      }
    }
  }

  void _moveCurrent(int delta) {
    final flat = ref.read(searchRunnerProvider.notifier).moveCurrent(delta);
    if (flat != null) _revealFlat(flat);
  }

  Future<void> _replaceCurrent() async {
    final root = ref.read(fileProvider);
    final replaced = await ref
        .read(searchRunnerProvider.notifier)
        .replaceCurrent(root);
    if (!replaced || !mounted) return;

    // Refresh the file tree and reconcile any open tab whose buffer now
    // differs from the rewritten file on disk.
    await ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    if (!mounted) return;
    await ref
        .read(tabbedViewControllerProvider.notifier)
        .checkExternalChanges(context);
  }

  Future<void> _replaceAll(BuildContext context) async {
    final root = ref.read(fileProvider);
    if (root == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (_, r, child) {
          final state = r.watch(searchRunnerProvider);
          return AlertDialog(
            title: Text(_tr(r, I18nKey.searchConfirmReplaceTitle)),
            content: Text(
              _tr(r, I18nKey.searchConfirmReplaceBody, {
                'files': '${state.matchedFiles}',
                'matches': '${state.totalMatches}',
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_tr(r, I18nKey.commonCancel)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_tr(r, I18nKey.editorReplaceAll)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    final count = await ref
        .read(searchRunnerProvider.notifier)
        .replaceAll(root);

    // Refresh the file tree and reconcile any open tabs whose buffer now
    // differs from the rewritten file on disk.
    await ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    if (!context.mounted) return;
    await ref
        .read(tabbedViewControllerProvider.notifier)
        .checkExternalChanges(context);

    // Files changed on disk, so the scan cache is stale — rescan.
    if (mounted) {
      ref.read(searchRunnerProvider.notifier).runSearch(root, rescan: true);
    }

    if (context.mounted && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(ref, I18nKey.searchReplaceDone, {'matches': '$count'}),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searchState = ref.watch(searchRunnerProvider);
    final root = ref.watch(fileProvider);
    final flats = searchState.flatMatches;
    final currentMatch = flats.isEmpty
        ? null
        : flats[searchState.currentMatchIndex.clamp(0, flats.length - 1)];

    return Scaffold(
      body: Column(
        children: [
          _SearchBar(
            onOpenFlatMatch: _revealFlat,
            onMoveCurrent: _moveCurrent,
            onReplaceCurrent: _replaceCurrent,
            onReplaceAll: () => _replaceAll(context),
          ),
          _buildStatusRow(searchState, scheme, root),
          const Divider(height: 1),
          Expanded(
            child: _buildResults(searchState, root, scheme, currentMatch),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    SearchState searchState,
    ColorScheme scheme,
    Directory? root,
  ) {
    if (root == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _tr(ref, I18nKey.searchNoProject),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (searchState.status == SearchStatus.running) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _tr(ref, I18nKey.searchScanned, {
                'scanned': '${searchState.scanned}',
                'total': '${searchState.total}',
              }),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => ref.read(searchRunnerProvider.notifier).cancel(),
              child: Text(_tr(ref, I18nKey.searchCancel)),
            ),
          ],
        ),
      );
    }

    if (searchState.status == SearchStatus.done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(
              _tr(ref, I18nKey.searchFilesMatched, {
                'files': '${searchState.matchedFiles}',
              }),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Text('  ·  ', style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(
              _tr(ref, I18nKey.searchMatchesInFile, {
                'count': '${searchState.totalMatches}',
              }),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  ref.read(searchCollapsedProvider.notifier).state = {},
              child: Text(_tr(ref, I18nKey.searchExpandAll)),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(searchCollapsedProvider.notifier).state = {
                    for (final r in searchState.results) r.filePath,
                  },
              child: Text(_tr(ref, I18nKey.searchCollapseAll)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildResults(
    SearchState searchState,
    Directory? root,
    ColorScheme scheme,
    FlatSearchMatch? currentMatch,
  ) {
    if (root == null) {
      return Center(
        child: Text(
          _tr(ref, I18nKey.searchNoProject),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (searchState.status == SearchStatus.done &&
        searchState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: scheme.outline, size: 32),
            const SizedBox(height: 8),
            Text(
              _tr(ref, I18nKey.searchEmpty),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (searchState.results.isEmpty) {
      return const SizedBox.shrink();
    }

    return SearchResultsView(
      results: searchState.results,
      root: root,
      currentMatch: currentMatch,
      onOpenMatch: _openFromView,
    );
  }
}

/// Flat find/replace bar at the top of the search page.
///
/// Mirrors the editor's Ctrl+F find widget — same controls, same interaction —
/// but sits directly on the page instead of in a floating panel.
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar({
    required this.onOpenFlatMatch,
    required this.onMoveCurrent,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
  });

  final void Function(FlatSearchMatch match) onOpenFlatMatch;
  final void Function(int delta) onMoveCurrent;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

/// Height shared by both inputs.
///
/// The find input also hosts the option toggles, so if each field sized itself
/// the two rows would end up different heights. One constant for both keeps
/// them identical.
const double _fieldHeight = 32;

/// Side of the square toolbar buttons.
const double _iconButtonSize = 28;

/// Side of the option toggles (`Aa` / `ab` / `.*`).
const double _toggleSize = 24;

/// Clear space an option toggle keeps between its painted square and the find
/// input's top and bottom edges. Neighbouring toggles each carry half of it so
/// their squares end up this far apart — the same room they keep from the
/// edges — and the row closes with a half inset so the last square keeps the
/// full distance from the input's right edge.
const double _toggleInset = 3;

/// Gap between the elements of a row.
const double _barGap = 6;

/// Gap between the find row and the replace row.
const double _rowGap = 4;

class _SearchBarState extends ConsumerState<_SearchBar> {
  final _queryController = TextEditingController();
  final _replaceController = TextEditingController();

  /// Owned here so rebuilding the bar (every keystroke rebuilds it) never
  /// recreates the focus nodes.
  final _queryFocusNode = FocusNode();
  final _replaceFocusNode = FocusNode();

  Timer? _debounce;
  bool _replaceMode = false;

  @override
  void initState() {
    super.initState();
    final options = ref.read(searchOptionsProvider);
    _queryController.text = options.pattern;
    _replaceController.text = options.replaceText;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _replaceController.dispose();
    _queryFocusNode.dispose();
    _replaceFocusNode.dispose();
    super.dispose();
  }

  void _runNow() {
    _debounce?.cancel();
    ref.read(searchRunnerProvider.notifier).runSearch(ref.read(fileProvider));
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _runNow);
  }

  void _updateOptions(SearchOptions Function(SearchOptions) updater) {
    final current = ref.read(searchOptionsProvider);
    ref.read(searchOptionsProvider.notifier).state = updater(current);
  }

  void _onQueryChanged(String value) {
    _updateOptions((o) => o.copyWith(pattern: value));
    if (value.isEmpty) {
      _debounce?.cancel();
      ref.read(searchRunnerProvider.notifier).clear();
      return;
    }
    _scheduleSearch();
  }

  /// Match toggles apply instantly: with the scan cached this is an in-memory
  /// re-match, so there is nothing to debounce.
  void _toggleOption(SearchOptions Function(SearchOptions) updater) {
    _updateOptions(updater);
    _runNow();
  }

  void _close() {
    if (_replaceMode) {
      setState(() => _replaceMode = false);
      return;
    }
    _queryController.clear();
    _updateOptions((o) => o.copyWith(pattern: ''));
    _debounce?.cancel();
    ref.read(searchRunnerProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurface;
    final fieldColor = Color.alphaBlend(
      foreground.withAlpha(12),
      scheme.surface,
    );
    final options = ref.watch(searchOptionsProvider);
    final searchState = ref.watch(searchRunnerProvider);
    final totalMatches = searchState.flatMatches.length;

    String tr(I18nKey key) => translateForWidget(ref, key);

    final counter = _matchCounter(
      tr,
      foreground: foreground,
      hasQuery: options.pattern.isNotEmpty,
      total: totalMatches,
      current: searchState.currentMatchIndex,
    );

    // Both rows keep the same leading and trailing widths — the replace row
    // reserves the counter's width as well — so their expanded inputs resolve
    // to the same width.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _BarIconButton(
                  icon: _replaceMode ? Icons.expand_more : Icons.chevron_right,
                  tooltip: tr(
                    _replaceMode
                        ? I18nKey.editorFindHideReplace
                        : I18nKey.editorFindShowReplace,
                  ),
                  foreground: foreground,
                  onPressed: () => setState(() => _replaceMode = !_replaceMode),
                ),
                const SizedBox(width: 4),
                Icon(Icons.search, size: 16, color: foreground),
                const SizedBox(width: _barGap),
                Expanded(
                  child: _field(
                    controller: _queryController,
                    focusNode: _queryFocusNode,
                    hintText: tr(I18nKey.editorFindHint),
                    foreground: foreground,
                    fillColor: fieldColor,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _runNow(),
                    trailing: [
                      _FindToggle(
                        label: 'Aa',
                        tooltip: tr(I18nKey.editorFindCaseSensitive),
                        active: options.caseSensitive,
                        foreground: foreground,
                        onPressed: () => _toggleOption(
                          (o) => o.copyWith(caseSensitive: !o.caseSensitive),
                        ),
                      ),
                      _FindToggle(
                        label: 'ab',
                        tooltip: tr(I18nKey.editorFindWholeWord),
                        active: options.wholeWord,
                        foreground: foreground,
                        onPressed: () => _toggleOption(
                          (o) => o.copyWith(wholeWord: !o.wholeWord),
                        ),
                      ),
                      _FindToggle(
                        label: '.*',
                        tooltip: tr(I18nKey.editorFindRegex),
                        active: options.isRegExp,
                        foreground: foreground,
                        onPressed: () => _toggleOption(
                          (o) => o.copyWith(isRegExp: !o.isRegExp),
                        ),
                      ),
                      // The trailing half of the last toggle's side inset, so
                      // the cluster ends the same distance from the input's
                      // right edge that the squares keep from the top and
                      // bottom edges.
                      const SizedBox(width: _toggleInset / 2),
                    ],
                  ),
                ),
                const SizedBox(width: _barGap),
                counter.widget,
                _BarIconButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: tr(I18nKey.editorFindPrevious),
                  foreground: foreground,
                  onPressed: totalMatches > 0
                      ? () => widget.onMoveCurrent(-1)
                      : null,
                ),
                _BarIconButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: tr(I18nKey.editorFindNext),
                  foreground: foreground,
                  onPressed: totalMatches > 0
                      ? () => widget.onMoveCurrent(1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: _rowGap),
            if (_replaceMode)
              Row(
                children: [
                  // The find row's expand button, kept as empty space so both
                  // inputs start at the same x.
                  const SizedBox(width: _iconButtonSize + 4),
                  Icon(Icons.find_replace, size: 16, color: foreground),
                  const SizedBox(width: _barGap),
                  Expanded(
                    child: _field(
                      controller: _replaceController,
                      focusNode: _replaceFocusNode,
                      hintText: tr(I18nKey.editorReplaceHint),
                      foreground: foreground,
                      fillColor: fieldColor,
                      onChanged: (value) =>
                          _updateOptions((o) => o.copyWith(replaceText: value)),
                      onSubmitted: (_) => widget.onReplaceCurrent(),
                    ),
                  ),
                  const SizedBox(width: _barGap),
                  SizedBox(width: counter.width),
                  _BarIconButton(
                    icon: Icons.check,
                    tooltip: tr(I18nKey.editorReplaceApply),
                    foreground: foreground,
                    onPressed: totalMatches > 0
                        ? widget.onReplaceCurrent
                        : null,
                  ),
                  _BarIconButton(
                    icon: Icons.done_all,
                    tooltip: tr(I18nKey.editorReplaceAll),
                    foreground: foreground,
                    onPressed: totalMatches > 0 ? widget.onReplaceAll : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// One input of the bar.
  ///
  /// The box draws the fill, the outline and the focus colour itself, which
  /// lets both inputs share [_fieldHeight] and lets the find input keep the
  /// option toggles inside its border. The box and the toggles use the same
  /// [AppCornerRadiiX.innerCorners] radius so the nesting reads as one shape.
  Widget _field({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required Color foreground,
    required Color fillColor,
    required ValueChanged<String> onChanged,
    ValueChanged<String>? onSubmitted,
    List<Widget> trailing = const [],
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) => Container(
        height: _fieldHeight,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: context.innerCorners,
          border: Border.all(
            color: focusNode.hasFocus
                ? foreground.withAlpha(120)
                : foreground.withAlpha(46),
          ),
        ),
        child: child,
      ),
      // Built once and reused on focus changes; only the box decoration needs
      // to be rebuilt there.
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              // The row centres the editable vertically, so the text sits
              // mid-height without any alignment tweaks.
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 1,
                style: TextStyle(color: foreground, fontSize: 13),
                cursorColor: foreground,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                decoration: InputDecoration.collapsed(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: foreground.withAlpha(110),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }

  /// Match counter styled like the editor's: measured width, `current/total`
  /// or a red "no results" hint. Returns the width it occupies so the replace
  /// row can reserve the same slot.
  ({double width, Widget widget}) _matchCounter(
    String Function(I18nKey) tr, {
    required Color foreground,
    required bool hasQuery,
    required int total,
    required int current,
  }) {
    final noResults = hasQuery && total == 0;
    final text = !hasQuery
        ? ''
        : noResults
        ? tr(I18nKey.editorFindNoResults)
        : '${(current + 1).clamp(1, total)}/$total';
    final color = noResults
        ? Colors.redAccent.withAlpha(220)
        : foreground.withAlpha(200);
    final textStyle = TextStyle(color: color, fontSize: 11);
    if (text.isEmpty) {
      return (width: 0, widget: const SizedBox.shrink());
    }
    // Measure the label so the counter never reserves more room than it uses.
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = max(34.0, painter.width + 6);
    painter.dispose();
    return (
      width: width,
      widget: Container(
        width: width,
        alignment: Alignment.center,
        child: Text(text, textAlign: TextAlign.center, style: textStyle),
      ),
    );
  }
}

/// One option button (`Aa` / `ab` / `.*`) inside the find input.
///
/// The [Padding] keeps the painted square away from the input's outline and
/// from the neighbouring toggles, so the hover and selected states never sit
/// flush against either. Horizontally each side carries half the inset, since
/// adjacent paddings add up; vertical carries it whole.
class _FindToggle extends StatefulWidget {
  const _FindToggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool active;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  State<_FindToggle> createState() => _FindToggleState();
}

class _FindToggleState extends State<_FindToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.foreground;
    final Color background;
    final Color borderColor;
    if (widget.active) {
      background = color.withAlpha(36);
      borderColor = color.withAlpha(130);
    } else if (_hovered) {
      background = color.withAlpha(20);
      borderColor = color.withAlpha(90);
    } else {
      background = Colors.transparent;
      borderColor = Colors.transparent;
    }
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        child: Padding(
          // Vertically the full inset — it is the square's only clearance from
          // the input's edges. Horizontally half of it: the neighbouring
          // toggle's half adds up to one full inset between the squares.
          padding: const EdgeInsets.symmetric(
            horizontal: _toggleInset / 2,
            vertical: _toggleInset,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: _toggleSize,
                height: _toggleSize,
                alignment: Alignment.center,
                // Same radius as the input, so the two shapes match.
                decoration: BoxDecoration(
                  borderRadius: context.innerCorners,
                  color: background,
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color.withAlpha(widget.active ? 255 : 150),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon button matching the editor find bar's buttons.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      // Without this the Material tap target inflates the button well past
      // [_iconButtonSize], which would push the inputs out of alignment.
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      color: foreground.withAlpha(215),
      disabledColor: foreground.withAlpha(70),
      hoverColor: foreground.withAlpha(26),
      focusColor: Colors.transparent,
      highlightColor: foreground.withAlpha(40),
      splashRadius: _iconButtonSize / 2,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _iconButtonSize,
        height: _iconButtonSize,
      ),
    );
  }
}
