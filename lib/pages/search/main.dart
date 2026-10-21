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
    final replaced =
        await ref.read(searchRunnerProvider.notifier).replaceCurrent(root);
    if (!replaced || !mounted) return;

    // Refresh the file tree and reconcile any open tab whose buffer now
    // differs from the rewritten file on disk.
    await ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
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
              _tr(
                r,
                I18nKey.searchConfirmReplaceBody,
                {
                  'files': '${state.matchedFiles}',
                  'matches': '${state.totalMatches}',
                },
              ),
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

    final count =
        await ref.read(searchRunnerProvider.notifier).replaceAll(root);

    // Refresh the file tree and reconcile any open tabs whose buffer now
    // differs from the rewritten file on disk.
    await ref.read(localFileItemsProvider.notifier).buildRootFileListItems();
    await ref
        .read(tabbedViewControllerProvider.notifier)
        .checkExternalChanges(context);

    // Files changed on disk, so the scan cache is stale — rescan.
    if (mounted) {
      ref
          .read(searchRunnerProvider.notifier)
          .runSearch(root, rescan: true);
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
          Expanded(child: _buildResults(searchState, root, scheme, currentMatch)),
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
              onPressed: () =>
                  ref.read(searchRunnerProvider.notifier).cancel(),
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
              _tr(ref, I18nKey.searchFilesMatched,
                  {'files': '${searchState.matchedFiles}'}),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Text(
              '  ·  ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Text(
              _tr(ref, I18nKey.searchMatchesInFile,
                  {'count': '${searchState.totalMatches}'}),
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
/// Its two rows mirror the editor's Ctrl+F find bar (same controls, sizes and
/// visuals) but sit directly on the page — no floating rounded panel,
/// elevation or outline around them.
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

class _SearchBarState extends ConsumerState<_SearchBar> {
  static const double _rowHeight = 32;
  static const double _buttonSize = 28;

  /// Breathing gap between the find and replace rows; the fields fill their
  /// rows and would otherwise touch.
  static const double _replaceRowGap = 4;
  static const double _inset = 8;
  static const double _leadingIconSize = 16;
  static const double _gapAfterLeadingButton = 4;
  static const double _gapAroundField = 6;
  static const double _matchCounterMinWidth = 34;
  static const double _matchCounterPadding = 6;

  /// Leading offset of both input rows: the leading button plus its gap, the
  /// leading icon and the gap that separates it from the input. The replace
  /// row has no leading button, so it pads that slot instead, which keeps both
  /// inputs starting at the same x position.
  static const double _leadingWidth =
      _buttonSize + _gapAfterLeadingButton + _leadingIconSize + _gapAroundField;

  /// Width of everything between the find input and the right edge except the
  /// match counter: the gap in front of it plus the two navigation buttons.
  /// The counter's measured width is added at build time. The three option
  /// toggles live inside the find input as its suffix, so they don't count
  /// here.
  static const double _trailingWidth = _gapAroundField + _buttonSize * 2;

  final _queryController = TextEditingController();
  final _replaceController = TextEditingController();
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
    final background = scheme.surface;
    final fieldBackground = Color.alphaBlend(
      foreground.withAlpha(12),
      background,
    );
    final options = ref.watch(searchOptionsProvider);
    final searchState = ref.watch(searchRunnerProvider);
    final totalMatches = searchState.flatMatches.length;

    String tr(I18nKey key) => translateForWidget(ref, key);

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
      child: Container(
        decoration: BoxDecoration(
          color: background,
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant.withAlpha(60)),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: _inset,
          vertical: 6,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final counter = _matchCounter(
              tr,
              foreground: foreground,
              hasQuery: options.pattern.isNotEmpty,
              total: totalMatches,
              current: searchState.currentMatchIndex,
            );
            // Both inputs get the same width so their left and right edges
            // line up, independent of how wide the trailing controls are. The
            // counter only reserves the width its text needs, so both inputs
            // grow into the space it leaves free.
            final fieldWidth = max(
              0.0,
              constraints.maxWidth -
                  _leadingWidth -
                  counter.width -
                  _trailingWidth,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _rowHeight,
                  child: Row(
                    children: [
                      _BarIconButton(
                        icon: _replaceMode
                            ? Icons.expand_more
                            : Icons.chevron_right,
                        tooltip: tr(
                          _replaceMode
                              ? I18nKey.editorFindHideReplace
                              : I18nKey.editorFindShowReplace,
                        ),
                        foreground: foreground,
                        onPressed: () =>
                            setState(() => _replaceMode = !_replaceMode),
                      ),
                      const SizedBox(width: _gapAfterLeadingButton),
                      Icon(
                        Icons.search,
                        size: _leadingIconSize,
                        color: foreground,
                      ),
                      const SizedBox(width: _gapAroundField),
                      SizedBox(
                        width: fieldWidth,
                        child: _textField(
                          context,
                          controller: _queryController,
                          hintText: tr(I18nKey.editorFindHint),
                          fieldBackground: fieldBackground,
                          foreground: foreground,
                          onChanged: _onQueryChanged,
                          onSubmitted: (_) => _runNow(),
                          // VSCode-style: the option toggles live inside the
                          // find input, along its right edge.
                          suffix: Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FindToggle(
                                  label: 'Aa',
                                  tooltip:
                                      tr(I18nKey.editorFindCaseSensitive),
                                  active: options.caseSensitive,
                                  foreground: foreground,
                                  onPressed: () => _toggleOption(
                                    (o) => o.copyWith(
                                      caseSensitive: !o.caseSensitive,
                                    ),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: _gapAroundField),
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
                ),
                const SizedBox(height: _replaceRowGap),
                if (_replaceMode)
                  SizedBox(
                    height: _rowHeight,
                    child: Row(
                      children: [
                        // Pads the slot the find row's leading button uses so
                        // the two inputs share the same left edge.
                        const SizedBox(
                          width: _buttonSize + _gapAfterLeadingButton,
                        ),
                        Icon(
                          Icons.find_replace,
                          size: _leadingIconSize,
                          color: foreground,
                        ),
                        const SizedBox(width: _gapAroundField),
                        SizedBox(
                          width: fieldWidth,
                          child: _textField(
                            context,
                            controller: _replaceController,
                            hintText: tr(I18nKey.editorReplaceHint),
                            fieldBackground: fieldBackground,
                            foreground: foreground,
                            onChanged: (value) => _updateOptions(
                              (o) => o.copyWith(replaceText: value),
                            ),
                            onSubmitted: (_) => widget.onReplaceCurrent(),
                          ),
                        ),
                        // The replace row has fewer trailing buttons, so the
                        // leftover width is left blank.
                        const Spacer(),
                        const SizedBox(width: _gapAroundField),
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
                          onPressed: totalMatches > 0
                              ? widget.onReplaceAll
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required String hintText,
    required Color fieldBackground,
    required Color foreground,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSubmitted,
    Widget? suffix,
  }) {
    final borderColor = foreground.withAlpha(46);
    return TextField(
      controller: controller,
      maxLines: 1,
      style: TextStyle(color: foreground, fontSize: 13),
      cursorColor: foreground,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: fieldBackground,
        hintText: hintText,
        hintStyle: TextStyle(color: foreground.withAlpha(110), fontSize: 13),
        // Vertical 10 keeps the decorator's intrinsic height at the 32px row
        // height even under the app's compact density tier (which shrinks the
        // default to ~26px), so the suffix toggles get 5px of air on all
        // sides, matching the right inset.
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        // `suffixIcon` rather than `suffix`: the decorator fades `suffix` out
        // while the field is empty and unfocused (it wraps it in the
        // label-withdraw opacity), but the option toggles must always stay
        // visible. suffixIcon's default 48x48 minimum is relaxed via
        // suffixIconConstraints so it fits the 32px row.
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: context.nestedCorners(_inset),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: context.nestedCorners(_inset),
          borderSide: BorderSide(color: foreground.withAlpha(160)),
        ),
      ),
    );
  }

  /// Match counter styled like the editor's: measured width, `current/total`
  /// or a red "no results" hint. Returns the width it occupies so the caller
  /// can size both inputs against it.
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
    final width = max(_matchCounterMinWidth, painter.width + _matchCounterPadding);
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

/// Small square toggle (Aa / ab / .*) styled like the editor find bar's option
/// buttons.
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
  /// 22px inside the 32px row centers with 5px of air above and below, which
  /// matches the suffix's right inset so the toggle's (selected) outline keeps
  /// an equal gap to the input's border on all sides.
  static const double _size = _SearchBarState._buttonSize - 6;

  /// Sibling toggles share the bar's inset, so every button in the row has the
  /// same corner radius.
  static const double _inset = _SearchBarState._inset;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // VSCode-style toggle: the selected state draws a thin accent outline
    // over a subtle tint, hover paints only an inner highlight fill, and the
    // idle state stays a plain label.
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color background;
    final Color borderColor;
    if (widget.active) {
      background = accent.withAlpha(28);
      borderColor = accent;
    } else if (_hovered) {
      background = widget.foreground.withAlpha(26);
      borderColor = Colors.transparent;
    } else {
      background = Colors.transparent;
      borderColor = Colors.transparent;
    }
    // `container: true` prevents adjacent toolbar buttons from merging this
    // tooltip's semantics anchor into one shared node.
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        child: Padding(
          // Separates adjacent toggles without shrinking the painted square.
          padding: const EdgeInsets.only(left: 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: context.nestedCorners(_inset),
                  color: background,
                  // Hover keeps the border slot transparent so the states can
                  // never paint a second, offset rectangle.
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.foreground.withAlpha(
                      widget.active ? 255 : _hovered ? 210 : 150,
                    ),
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
      color: foreground.withAlpha(215),
      disabledColor: foreground.withAlpha(70),
      hoverColor: foreground.withAlpha(26),
      focusColor: Colors.transparent,
      highlightColor: foreground.withAlpha(40),
      splashRadius: _SearchBarState._buttonSize / 2,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _SearchBarState._buttonSize,
        height: _SearchBarState._buttonSize,
      ),
    );
  }
}
