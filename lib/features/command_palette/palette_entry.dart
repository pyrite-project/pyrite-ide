import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a palette session started, which biases how results are ranked.
enum PaletteLaunchMode {
  /// `Cmd/Ctrl+Shift+P`: commands, navigation and settings first.
  commands,

  /// `Cmd/Ctrl+P`: project files first, for quick open.
  files,
}

/// The group a [PaletteEntry] is listed under.
enum PaletteCategory { command, file, navigation, setting }

/// Runs a [PaletteEntry]'s action.
///
/// The callback receives the context the palette was opened from and the
/// palette's live [WidgetRef]; the dialog awaits it before closing so a
/// callback can show a confirmation or retry dialog.
typedef PaletteExecuteCallback =
    Future<void> Function(BuildContext context, WidgetRef ref);

/// One selectable row in the command palette.
///
/// A palette entry is presentation + an action; the widget layer resolves
/// [title] and [subtitle] to already-translated strings when it builds the
/// entry, so ranking can stay a pure function over plain text.
@immutable
class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.title,
    required this.category,
    this.subtitle,
    this.keywords = const <String>[],
    this.enabled = true,
    this.icon,
    this.onSelect,
    this.searchText,
  });

  /// Stable identity used for recents and deduplication.
  final String id;

  /// Display title (already localized by the caller).
  final String title;

  /// Optional second line, e.g. a file's project-relative path.
  final String? subtitle;

  final PaletteCategory category;

  /// Extra searchable words that are not shown to the user.
  final List<String> keywords;

  /// Disabled entries stay visible but cannot be run.
  final bool enabled;

  final IconData? icon;

  final PaletteExecuteCallback? onSelect;

  /// Pre-lowercased haystack used for ranking.
  ///
  /// File entries set this to their relative path because the index can hold
  /// tens of thousands of them and rebuilding the text per keystroke is
  /// wasteful. When null the ranker derives it from [title], [subtitle] and
  /// [keywords].
  final String? searchText;

  /// Whether activating this entry would run an action.
  bool get canExecute => enabled && onSelect != null;

  PaletteEntry copyWith({
    String? id,
    String? title,
    String? subtitle,
    PaletteCategory? category,
    List<String>? keywords,
    bool? enabled,
    IconData? icon,
    PaletteExecuteCallback? onSelect,
    String? searchText,
  }) => PaletteEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    category: category ?? this.category,
    keywords: keywords ?? this.keywords,
    enabled: enabled ?? this.enabled,
    icon: icon ?? this.icon,
    onSelect: onSelect ?? this.onSelect,
    searchText: searchText ?? this.searchText,
  );
}
