import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many recently used entries the palette remembers.
///
/// The recents row is a convenience, not a history: six entries is what fits
/// above the fold on a short window without pushing the commands away.
const int maxRecentPaletteEntries = 6;

/// The palette entries the user ran, newest first.
///
/// Kept in memory for the session only. Persisting it would make the palette
/// depend on `app.json` and would show entries from a previous project, which
/// is worse than an empty row on a fresh start.
class RecentPaletteIds extends StateNotifier<List<String>> {
  RecentPaletteIds() : super(const <String>[]);

  /// Records [id] as the most recently used entry.
  ///
  /// Re-running an entry moves it to the front instead of adding a duplicate,
  /// so the list stays a set of ids ordered by last use.
  void record(String id) {
    if (id.isEmpty) return;
    final next = <String>[
      id,
      for (final existing in state)
        if (existing != id) existing,
    ];
    if (next.length > maxRecentPaletteEntries) {
      next.removeRange(maxRecentPaletteEntries, next.length);
    }
    state = List<String>.unmodifiable(next);
  }

  /// Forgets every remembered entry.
  void clear() => state = const <String>[];
}

/// The ids in [RecentPaletteIds], watched by the palette to build its recents
/// row and to bias ranking.
final StateNotifierProvider<RecentPaletteIds, List<String>>
recentPaletteIdsProvider =
    StateNotifierProvider<RecentPaletteIds, List<String>>(
      (ref) => RecentPaletteIds(),
    );
