import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';

import './md3_widgets.dart';

/// The find option a key event toggles (Alt+C / Alt+W / Alt+R, or Cmd+Alt on
/// Apple platforms), if any.
SearchOption? searchOptionForKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  bool matches(List<SingleActivator> activators) =>
      activators.any((activator) => activator.accepts(event, keyboard));
  if (matches(findCaseSensitiveActivators())) return SearchOption.caseSensitive;
  if (matches(findWholeWordActivators())) return SearchOption.wholeWord;
  if (matches(findRegexActivators())) return SearchOption.regex;
  return null;
}

/// Tooltip for a find option toggle, naming its shortcut.
String searchOptionTooltip(String Function(I18nKey) tr, SearchOption option) {
  return switch (option) {
    SearchOption.caseSensitive =>
      '${tr(I18nKey.editorFindCaseSensitive)} (${findCaseSensitiveShortcutLabel()})',
    SearchOption.wholeWord =>
      '${tr(I18nKey.editorFindWholeWord)} (${findWholeWordShortcutLabel()})',
    SearchOption.regex =>
      '${tr(I18nKey.editorFindRegex)} (${findRegexShortcutLabel()})',
  };
}

/// One option button (Aa / ab / .*) of a search field.
///
/// The hover fill, the active fill and the border are all painted by the same
/// [BoxDecoration] on the same square, so no state can draw a rectangle offset
/// from the others. The gap between neighbouring buttons comes from padding
/// around that square rather than a margin on it.
class SearchOptionToggle extends StatefulWidget {
  const SearchOptionToggle({
    super.key,
    required this.option,
    required this.tooltip,
    required this.active,
    required this.foreground,
    required this.onPressed,
    this.size = 26,
    this.cornerInset = 8,
    this.spacing = 2,
  });

  final SearchOption option;
  final String tooltip;
  final bool active;
  final Color foreground;
  final VoidCallback onPressed;

  /// Edge length of the painted square.
  final double size;

  /// Distance from the enclosing rounded surface, so sibling toggles keep
  /// arcs concentric with it.
  final double cornerInset;

  /// Clear space kept on the square's leading side. Adjacent toggles add
  /// theirs together, so this is half the gap the cluster shows, and the same
  /// distance the first square keeps from the field's text.
  final double spacing;

  @override
  State<SearchOptionToggle> createState() => _SearchOptionToggleState();
}

class _SearchOptionToggleState extends State<SearchOptionToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.foreground;
    final active = widget.active;
    // `container: true` prevents adjacent toolbar buttons from merging this
    // tooltip's semantics anchor into one shared node. See
    // flutter/flutter#182444.
    return TooltipAnchor(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        button: true,
        toggled: active,
        child: Padding(
          // Separates adjacent toggles without shrinking the painted square.
          padding: EdgeInsets.only(left: widget.spacing),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Container(
                width: widget.size,
                height: widget.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: context.nestedCorners(widget.cornerInset),
                  color: active
                      ? foreground.withAlpha(36)
                      : _hovered
                      ? foreground.withAlpha(20)
                      : Colors.transparent,
                  // Hover reuses the border slot so it can never paint a
                  // second, offset rectangle next to the active one.
                  border: Border.all(
                    color: active
                        ? foreground.withAlpha(130)
                        : _hovered
                        ? foreground.withAlpha(90)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  widget.option.label,
                  style: TextStyle(
                    color: foreground.withAlpha(active ? 255 : 150),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    // VS Code draws "ab" over an underline for whole word.
                    decoration: widget.option == SearchOption.wholeWord
                        ? TextDecoration.underline
                        : null,
                    decorationColor: foreground.withAlpha(active ? 255 : 150),
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

/// A compact search input with the `Aa` / `ab` / `.*` toggles inside its
/// trailing edge, like VS Code's find widget.
///
/// The box mirrors the search page's find input: the same height, corner
/// radius, fill, outline and typography, with the magnifier sitting outside
/// the box, so both places read as the same control.
///
/// Alt+C / Alt+W / Alt+R toggle the options while the field has focus, and
/// Escape clears the text.
class OptionsSearchField extends ConsumerStatefulWidget {
  const OptionsSearchField({
    super.key,
    required this.controller,
    required this.options,
    required this.onOptionsChanged,
    required this.onChanged,
    this.focusNode,
    this.hintText,
    this.hasError = false,
  });

  /// Height of the bordered box, shared with the search page's find input.
  static const double _fieldHeight = 32;

  /// Edge length of an option toggle's painted square.
  static const double _toggleSize = 24;

  /// Clear space a toggle's painted square keeps from the box's edges.
  static const double _toggleInset = 3;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final SearchOptions options;
  final ValueChanged<SearchOptions> onOptionsChanged;
  final ValueChanged<String> onChanged;
  final String? hintText;

  /// Outlines the field in the error color, e.g. for an invalid regex.
  final bool hasError;

  @override
  ConsumerState<OptionsSearchField> createState() => _OptionsSearchFieldState();
}

class _OptionsSearchFieldState extends ConsumerState<OptionsSearchField> {
  /// Backs the outline's focus state when the caller supplies no focus node.
  final FocusNode _fallbackFocusNode = FocusNode();

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  @override
  void dispose() {
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String tr(I18nKey key) => translateForWidget(ref, key);
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurface;
    final options = widget.options;
    final onOptionsChanged = widget.onOptionsChanged;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        final option = searchOptionForKeyEvent(event);
        if (option != null) {
          onOptionsChanged(options.toggled(option));
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            widget.controller.text.isNotEmpty) {
          widget.controller.clear();
          widget.onChanged('');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: foreground),
          const SizedBox(width: 6),
          Expanded(
            // Only the box decoration depends on focus, so the row inside is
            // built once and handed back unchanged.
            child: ListenableBuilder(
              listenable: _focusNode,
              builder: (context, child) => Container(
                height: OptionsSearchField._fieldHeight,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    foreground.withAlpha(12),
                    scheme.surface,
                  ),
                  borderRadius: context.innerCorners,
                  border: Border.all(
                    color: widget.hasError
                        ? scheme.error
                        : _focusNode.hasFocus
                        ? foreground.withAlpha(120)
                        : foreground.withAlpha(46),
                  ),
                ),
                child: child,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        maxLines: 1,
                        style: TextStyle(color: foreground, fontSize: 13),
                        cursorColor: foreground,
                        onChanged: widget.onChanged,
                        decoration: InputDecoration.collapsed(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: foreground.withAlpha(110),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final option in SearchOption.values)
                    SearchOptionToggle(
                      option: option,
                      tooltip: searchOptionTooltip(tr, option),
                      active: options.isOn(option),
                      foreground: foreground,
                      size: OptionsSearchField._toggleSize,
                      // Same radius as the box, so the nesting reads as one
                      // shape.
                      cornerInset: context.corners.gap,
                      // Half of the inset, so neighbouring squares sit
                      // [_toggleInset] apart — the gap the search page's find
                      // input uses.
                      spacing: OptionsSearchField._toggleInset / 2,
                      onPressed: () =>
                          onOptionsChanged(options.toggled(option)),
                    ),
                  // The squares carry their spacing on the leading side only,
                  // so the cluster's trailing clearance from the box's right
                  // edge needs the full inset here — the same distance the
                  // squares keep from the top and bottom edges.
                  const SizedBox(width: OptionsSearchField._toggleInset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
