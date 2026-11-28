import 'dart:math' as math;

import 'package:pyrite_ide/features/command_palette/palette_entry.dart';

/// Extra score for an entry that was used recently.
const int paletteRecentBoost = 120;

/// Reads the query the way the palette interprets it: a leading `>` is a mode
/// switch, not something to match.
String paletteEffectiveQuery(String raw) {
  var query = raw.trim();
  while (query.startsWith('>')) {
    query = query.substring(1).trimLeft();
  }
  return query;
}

/// Whether [raw] asks for commands only (`>` prefix).
bool paletteForcesCommands(String raw) => raw.trimLeft().startsWith('>');

/// Ranks [entries] for display in the palette.
///
/// The function is pure so the search behaviour can be tested without a
/// widget: it only looks at each entry's text, category, enabled state and id.
///
/// * A raw query starting with `>` excludes project files entirely.
/// * An empty (effective) query keeps every entry, ordered by enabled state,
///   category priority for [mode], and then title.
/// * A non-empty query keeps only entries whose title, subtitle or keywords
///   contain it, either as a contiguous substring or as an ordered
///   subsequence (the usual quick-open "opf" → "open file" behaviour), and
///   orders them by match quality with a bias for [mode].
/// * Recently used entries ([recentIds]) get a bonus, and disabled entries
///   always sort below enabled ones.
List<PaletteEntry> rankPaletteEntries(
  Iterable<PaletteEntry> entries, {
  required String query,
  required PaletteLaunchMode mode,
  Iterable<String> recentIds = const <String>[],
}) {
  final forceCommands = paletteForcesCommands(query);
  final effectiveQuery = paletteEffectiveQuery(query).toLowerCase();
  final recents = recentIds.toSet();

  final indexed = <({int index, PaletteEntry entry, int score})>[];
  var index = 0;
  for (final entry in entries) {
    if (forceCommands && entry.category == PaletteCategory.file) continue;
    final score = effectiveQuery.isEmpty
        ? 0
        : _entryScore(entry, effectiveQuery, mode: mode, recents: recents);
    if (effectiveQuery.isNotEmpty && score <= 0) continue;
    indexed.add((index: index++, entry: entry, score: score));
  }

  indexed.sort((a, b) {
    final left = a.entry;
    final right = b.entry;
    if (left.enabled != right.enabled) return left.enabled ? -1 : 1;
    if (effectiveQuery.isEmpty) {
      final leftRecent = recents.contains(left.id);
      final rightRecent = recents.contains(right.id);
      if (leftRecent != rightRecent) return leftRecent ? -1 : 1;
    } else {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
    }
    final byCategory = _categoryPriority(
      left.category,
      mode,
    ).compareTo(_categoryPriority(right.category, mode));
    if (byCategory != 0) return byCategory;
    final byTitle = left.title.toLowerCase().compareTo(
      right.title.toLowerCase(),
    );
    if (byTitle != 0) return byTitle;
    return a.index.compareTo(b.index);
  });

  return [for (final row in indexed) row.entry];
}

int _entryScore(
  PaletteEntry entry,
  String query, {
  required PaletteLaunchMode mode,
  required Set<String> recents,
}) {
  final title = entry.title.toLowerCase();
  final titleScore = _textScore(title, query);
  final haystack = entry.searchText ?? _searchHaystack(entry);
  final haystackScore = _textScore(haystack, query);
  // A title hit beats an equal match that is only in the path/description.
  final textScore = math.max(
    titleScore > 0 ? titleScore + 40 : 0,
    haystackScore,
  );
  if (textScore <= 0) return 0;
  var score = textScore + _modeBias(entry.category, mode);
  if (recents.contains(entry.id)) score += paletteRecentBoost;
  return score;
}

/// Lower-cased searchable text for entries that did not precompute one.
String _searchHaystack(PaletteEntry entry) {
  final buffer = StringBuffer(entry.title.toLowerCase());
  final subtitle = entry.subtitle;
  if (subtitle != null && subtitle.isNotEmpty) {
    buffer.write('\n${subtitle.toLowerCase()}');
  }
  for (final keyword in entry.keywords) {
    if (keyword.isNotEmpty) buffer.write('\n${keyword.toLowerCase()}');
  }
  return buffer.toString();
}

/// How good a match [query] is inside [text]; 0 means it does not match.
int _textScore(String text, String query) {
  if (query.isEmpty || text.isEmpty) return 0;
  if (text == query) return 1000;
  if (text.startsWith(query)) return 700;
  final index = text.indexOf(query);
  if (index >= 0) {
    final atBoundary = index == 0 || _isBoundary(text.codeUnitAt(index - 1));
    return (atBoundary ? 550 : 350) - math.min(index, 100);
  }
  return _subsequenceScore(text, query);
}

/// Separators that start a word in a title or a path segment.
bool _isBoundary(int codeUnit) =>
    codeUnit == 0x20 || // space
    codeUnit == 0x2F || // /
    codeUnit == 0x5C || // backslash
    codeUnit == 0x2E || // .
    codeUnit == 0x5F || // _
    codeUnit == 0x2D || // -
    codeUnit == 0x3A; // :

int _subsequenceScore(String text, String query) {
  var textIndex = 0;
  var firstMatch = -1;
  var lastMatch = -1;
  var gaps = 0;
  for (var queryIndex = 0; queryIndex < query.length; queryIndex++) {
    final target = query.codeUnitAt(queryIndex);
    var found = false;
    while (textIndex < text.length) {
      if (text.codeUnitAt(textIndex) == target) {
        if (firstMatch < 0) firstMatch = textIndex;
        if (lastMatch >= 0) gaps += textIndex - lastMatch - 1;
        lastMatch = textIndex;
        textIndex++;
        found = true;
        break;
      }
      textIndex++;
    }
    if (!found) return 0;
  }
  final gapPenalty = math.min<int>(gaps, 100);
  final startPenalty = math.min<int>(firstMatch, 40);
  return math.max<int>(40, 150 - gapPenalty - startPenalty);
}

int _modeBias(PaletteCategory category, PaletteLaunchMode mode) {
  return switch (mode) {
    PaletteLaunchMode.commands => switch (category) {
      PaletteCategory.command => 50,
      PaletteCategory.navigation => 30,
      PaletteCategory.setting => 20,
      PaletteCategory.file => 0,
    },
    PaletteLaunchMode.files => switch (category) {
      PaletteCategory.file => 80,
      PaletteCategory.command => 10,
      PaletteCategory.navigation => 0,
      PaletteCategory.setting => 0,
    },
  };
}

int _categoryPriority(PaletteCategory category, PaletteLaunchMode mode) {
  return switch (mode) {
    PaletteLaunchMode.commands => switch (category) {
      PaletteCategory.command => 0,
      PaletteCategory.navigation => 1,
      PaletteCategory.setting => 2,
      PaletteCategory.file => 3,
    },
    PaletteLaunchMode.files => switch (category) {
      PaletteCategory.file => 0,
      PaletteCategory.command => 1,
      PaletteCategory.navigation => 2,
      PaletteCategory.setting => 3,
    },
  };
}
