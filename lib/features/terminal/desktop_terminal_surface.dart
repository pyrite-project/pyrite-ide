/// The interactive desktop terminal surface: search bar, right-click menu and
/// clickable links layered over xterm's [TerminalView].
///
/// [TerminalView] is kept as the renderer and is not subclassed: everything
/// added here is a wrapper concern (an overlay, a menu triggered from the
/// already-exposed `onSecondaryTapUp`/`onTapUp` callbacks, and a key-event
/// hook). That keeps the vendored `xterm.dart` submodule untouched while the
/// terminal still behaves exactly like the upstream widget when none of these
/// features is used.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';
import 'package:pyrite_ide/features/terminal/terminal_context_menu.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_parser.dart';
import 'package:pyrite_ide/features/terminal/terminal_search.dart';
import 'package:pyrite_ide/features/terminal/terminal_search_bar.dart';
import 'package:xterm/xterm.dart';

class DesktopTerminalSurface extends StatefulWidget {
  const DesktopTerminalSurface({
    super.key,
    required this.terminal,
    required this.controller,
    required this.theme,
    required this.textStyle,
    this.onUrlClick,
    this.onFileReferenceClick,
  });

  /// The renderer state this surface drives. Taken apart from
  /// [DesktopTerminalSession] so the surface can be pumped in a widget test
  /// without a real PTY behind it — the session needs a live process, this
  /// widget does not.
  final Terminal terminal;
  final TerminalController controller;

  /// Theme after applying a program-declared background (OSC 11); computed by
  /// the caller so this widget never reads settings itself.
  final TerminalTheme theme;

  final TerminalStyle textStyle;

  /// Invoked for a clicked `http(s)://` reference.
  ///
  /// The surface finds the link and hands it out rather than opening it: the
  /// opener needs the message system (for the clipboard fallback), and pulling
  /// that into the renderer wrapper would make every widget test of the
  /// terminal need a Riverpod container. Null means link clicks are simply
  /// ignored, which is what a read-only output pane wants.
  final Future<void> Function(TerminalLink link)? onUrlClick;

  /// Invoked for a clicked `file:line` reference.
  final Future<void> Function(TerminalLink link)? onFileReferenceClick;

  @override
  State<DesktopTerminalSurface> createState() => _DesktopTerminalSurfaceState();
}

class _DesktopTerminalSurfaceState extends State<DesktopTerminalSurface> {
  /// Owned by this widget so the GlobalKey can reach [TerminalViewState] and,
  /// through it, the cell height needed to scroll a match into view. A
  /// GlobalKey preserves the subtree exactly like the ValueKey it replaces, so
  /// installing a theme contribution still does not recreate the renderer.
  final _terminalViewKey = GlobalKey<TerminalViewState>();

  /// Passed to the view so focus can go back to the terminal after the search
  /// bar closes; without it the terminal would stop receiving keystrokes.
  final _terminalFocusNode = FocusNode(debugLabel: 'desktop-terminal');

  final _searchFocusNode = FocusNode(debugLabel: 'terminal-search');
  final _searchController = TextEditingController();

  final _scrollController = ScrollController();

  TerminalSearchState _search = const TerminalSearchState();
  bool _searchOpen = false;

  /// Highlights are caller-owned in xterm, so they are disposed from here.
  late TerminalSearchHighlighter _highlighter;
  Timer? _refreshTimer;

  /// Output-driven refreshes are throttled: a build log can append hundreds of
  /// times a second, and re-scanning the whole scrollback per chunk makes the
  /// terminal unusable while the search bar is open.
  static const _refreshInterval = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _bindSession();
    // The search field's Enter/Esc must win over the text field's own handling,
    // so the node — not the widget — owns the callback.
    _searchFocusNode.onKeyEvent = _onSearchKeyEvent;
  }

  @override
  void didUpdateWidget(covariant DesktopTerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalOutput);
      _highlighter.dispose();
      _bindSession();
    }
  }

  void _bindSession() {
    _highlighter = TerminalSearchHighlighter(
      terminal: widget.terminal,
      controller: widget.controller,
    );
    widget.terminal.addListener(_onTerminalOutput);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    widget.terminal.removeListener(_onTerminalOutput);
    _highlighter.dispose();
    _searchFocusNode.onKeyEvent = null;
    _searchController.dispose();
    _searchFocusNode.dispose();
    _terminalFocusNode.dispose();
    // TerminalView only disposes a scroll controller it created itself.
    _scrollController.dispose();
    super.dispose();
  }

  /// True when the session's selection covers at least one non-empty cell.
  bool get _hasSelection {
    final selection = widget.controller.selection;
    if (selection == null || selection.isCollapsed) return false;
    return widget.terminal.buffer.getText(selection).isNotEmpty;
  }

  void _onTerminalOutput() {
    if (!_searchOpen || !_search.isActive) return;
    if (_refreshTimer?.isActive ?? false) return;
    _refreshTimer = Timer(_refreshInterval, () {
      if (!mounted || !_searchOpen) return;
      final lines = terminalBufferLines(widget.terminal);
      _applySearch(_search.refresh(lines));
    });
  }

  // ---- searching -----------------------------------------------------------

  void _openSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
    // Prefill with the selection, the same affordance the editor's find bar
    // offers; a terminal selection is usually exactly what is searched for.
    final selection = widget.controller.selection;
    if (selection != null && !selection.isCollapsed) {
      final text = widget.terminal.buffer.getText(selection).trim();
      if (text.isNotEmpty && !text.contains('\n')) {
        _searchController.text = text;
      }
    }
    _runSearch(_searchController.text);
    // The field only exists after the rebuild that the setState above
    // scheduled, so focus is moved once the frame is done. Requesting it now
    // would target a node that is not attached yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_searchOpen) return;
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _closeSearch() {
    if (!_searchOpen) return;
    _highlighter.dispose();
    setState(() {
      _searchOpen = false;
      _search = const TerminalSearchState();
    });
    _searchFocusNode.unfocus();
    _terminalFocusNode.requestFocus();
  }

  void _runSearch(String query, {bool? caseSensitive}) {
    final lines = terminalBufferLines(widget.terminal);
    _applySearch(
      _search.withQuery(
        lines,
        query,
        caseSensitive: caseSensitive ?? _search.caseSensitive,
      ),
    );
    _revealCurrentMatch();
  }

  void _applySearch(TerminalSearchState next) {
    final theme = widget.theme;
    _highlighter.apply(
      next,
      matchColor: theme.searchHitBackground.withValues(alpha: .7),
      currentColor: theme.searchHitBackgroundCurrent,
    );
    setState(() => _search = next);
  }

  void _stepSearch(int delta) {
    if (!_search.hasMatches) return;
    _applySearch(_search.cycle(delta));
    _revealCurrentMatch();
  }

  /// Scrolls the current match's line near the middle of the viewport.
  ///
  /// The line height only exists on the render object, which is why the view is
  /// wrapped in a GlobalKey. Before the first layout there is nothing to
  /// scroll; the highlight is still correct then, so the attempt is simply
  /// skipped.
  void _revealCurrentMatch() {
    final match = _search.current;
    if (match == null || !_scrollController.hasClients) return;
    // `mounted` guarantees the render box exists; reading lineHeight from a
    // detached render object would trip its non-null viewport key.
    final viewState = _terminalViewKey.currentState;
    if (viewState == null || !viewState.mounted) return;
    final lineHeight = viewState.renderTerminal.lineHeight;
    if (lineHeight <= 0) return;
    final position = _scrollController.position;
    final target =
        match.line * lineHeight -
        position.viewportDimension / 2 +
        lineHeight / 2;
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  // ---- context menu --------------------------------------------------------

  Future<void> _showContextMenu(Offset globalPosition) async {
    final action = await showTerminalContextMenu(
      context,
      globalPosition: globalPosition,
      hasSelection: _hasSelection,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case TerminalContextAction.copy:
        await _copySelection();
      case TerminalContextAction.paste:
        await _paste();
      case TerminalContextAction.selectAll:
        _selectAll();
      case TerminalContextAction.clear:
        _clear();
      case TerminalContextAction.search:
        _openSearch();
    }
  }

  Future<void> _copySelection() async {
    final selection = widget.controller.selection;
    if (selection == null) return;
    final text = widget.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    // `paste` honours bracketed paste mode, which is how a shell protects a
    // pasted multi-line block from executing immediately.
    widget.terminal.paste(text);
    widget.controller.clearSelection();
  }

  void _selectAll() {
    final terminal = widget.terminal;
    final buffer = terminal.buffer;
    widget.controller.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  /// Clears the screen and scrollback.
  ///
  /// The program is not signalled: an interactive shell redraws its prompt the
  /// next time it writes, while clearing the buffer directly also works for a
  /// REPL that is not reading stdin at this instant.
  void _clear() {
    widget.terminal.clear();
    widget.controller.clearSelection();
  }

  // ---- links ---------------------------------------------------------------

  Future<void> _openLinkAtCell(CellOffset cell) async {
    final buffer = widget.terminal.buffer;
    if (cell.y < 0 || cell.y >= buffer.lines.length) return;
    final text = terminalLineCellText(buffer.lines[cell.y]);
    final link = terminalLinkAtCell(parseTerminalLinks(text), cell.x);
    if (link == null) return;

    if (link.kind == TerminalLinkKind.url) {
      await widget.onUrlClick?.call(link);
      return;
    }
    await widget.onFileReferenceClick?.call(link);
  }

  // ---- keys ----------------------------------------------------------------

  KeyEventResult _onTerminalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    for (final activator in findActivators()) {
      if (!activator.accepts(event, HardwareKeyboard.instance)) continue;
      _openSearch();
      return KeyEventResult.handled;
    }
    // Escape only closes the bar; when it is not open it belongs to the program
    // (vim, less), so it must not be swallowed here.
    if (_searchOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _stepSearch(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TerminalView(
          widget.terminal,
          key: _terminalViewKey,
          controller: widget.controller,
          theme: widget.theme,
          textStyle: widget.textStyle,
          hardwareKeyboardOnly: true,
          focusNode: _terminalFocusNode,
          scrollController: _scrollController,
          onKeyEvent: _onTerminalKeyEvent,
          onTapUp: (details, cell) => _openLinkAtCell(cell),
          onSecondaryTapUp: (details, cell) =>
              _showContextMenu(details.globalPosition),
        ),
        if (_searchOpen)
          Positioned(
            top: 8,
            right: 20,
            child: TerminalSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              state: _search,
              onChanged: _runSearch,
              onPrevious: () => _stepSearch(-1),
              onNext: () => _stepSearch(1),
              onToggleCase: () => _runSearch(
                _searchController.text,
                caseSensitive: !_search.caseSensitive,
              ),
              onClose: _closeSearch,
            ),
          ),
      ],
    );
  }
}
