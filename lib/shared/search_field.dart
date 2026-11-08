import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/search_options.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';

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
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        container: true,
        button: true,
        toggled: active,
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
/// Alt+C / Alt+W / Alt+R toggle the options while the field has focus, and
/// Escape clears the text.
class OptionsSearchField extends ConsumerWidget {
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

  /// Gap between the field's rounded edge and the toggles inside it.
  static const double _toggleInset = 4;
  static const double _toggleSize = 22;
  static const double _fieldInset = 8;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final SearchOptions options;
  final ValueChanged<SearchOptions> onOptionsChanged;
  final ValueChanged<String> onChanged;
  final String? hintText;

  /// Outlines the field in the error color, e.g. for an invalid regex.
  final bool hasError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tr(I18nKey key) => translateForWidget(ref, key);
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurfaceVariant;
    final radius = context.nestedCorners(_fieldInset);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color),
    );
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
            controller.text.isNotEmpty) {
          controller.clear();
          onChanged('');
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 1,
        style: const TextStyle(fontSize: 13),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withAlpha(110),
          hintText: hintText,
          hintStyle: TextStyle(color: foreground.withAlpha(150), fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 9,
          ),
          prefixIcon: Icon(Icons.search, size: 16, color: foreground),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          suffixIcon: Padding(
            padding: const EdgeInsetsDirectional.only(end: _toggleInset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in SearchOption.values)
                  SearchOptionToggle(
                    option: option,
                    tooltip: searchOptionTooltip(tr, option),
                    active: options.isOn(option),
                    foreground: foreground,
                    size: _toggleSize,
                    cornerInset: _fieldInset + _toggleInset,
                    onPressed: () => onOptionsChanged(options.toggled(option)),
                  ),
              ],
            ),
          ),
          suffixIconConstraints: const BoxConstraints(minHeight: 32),
          enabledBorder: border(
            hasError ? scheme.error : scheme.outlineVariant,
          ),
          focusedBorder: border(hasError ? scheme.error : scheme.primary),
        ),
      ),
    );
  }
}
