import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/search/search_service.dart';

/// Editable query and match toggles, shared between the search bar and the
/// runner so a re-run always uses the latest values.
final searchOptionsProvider = StateProvider<SearchOptions>(
  (ref) => const SearchOptions(),
);

/// Files the user collapsed in the results list. Panel-local UI state rather
/// than something derived from results: a collapsed group stays collapsed across
/// searches, and paths that no longer match are simply ignored by the view.
final searchCollapsedProvider = StateProvider<Set<String>>((ref) => {});

enum SearchStatus { idle, running, done, cancelled, error }

/// One flattened match occurrence: enough to jump to it, highlight it in the
/// results list, and replace just it.
typedef FlatSearchMatch = ({
  String filePath,
  SearchMatch match,
  int rangeIndex,
  int ordinal,
});

/// Everything the results panel needs to render a search's outcome.
class SearchState {
  const SearchState({
    this.status = SearchStatus.idle,
    this.results = const [],
    this.scanned = 0,
    this.total = 0,
    this.matchedFiles = 0,
    this.matchedLines = 0,
    this.replaceCount = 0,
    this.currentMatchIndex = 0,
    this.error,
  });

  final SearchStatus status;
  final List<FileSearchResult> results;
  final int scanned;
  final int total;
  final int matchedFiles;
  final int matchedLines;
  final int replaceCount;

  /// Index into [flatMatches] of the occurrence prev/next navigation is on.
  final int currentMatchIndex;

  final String? error;

  SearchState copyWith({
    SearchStatus? status,
    List<FileSearchResult>? results,
    int? scanned,
    int? total,
    int? matchedFiles,
    int? matchedLines,
    int? replaceCount,
    int? currentMatchIndex,
    String? error,
  }) => SearchState(
    status: status ?? this.status,
    results: results ?? this.results,
    scanned: scanned ?? this.scanned,
    total: total ?? this.total,
    matchedFiles: matchedFiles ?? this.matchedFiles,
    matchedLines: matchedLines ?? this.matchedLines,
    replaceCount: replaceCount ?? this.replaceCount,
    currentMatchIndex: currentMatchIndex ?? this.currentMatchIndex,
    error: error ?? this.error,
  );

  int get totalMatches {
    var total = 0;
    for (final file in results) {
      total += file.matchCount;
    }
    return total;
  }

  /// All match occurrences in result order, flattened across files and lines.
  List<FlatSearchMatch> get flatMatches {
    final flat = <FlatSearchMatch>[];
    for (final file in results) {
      // Ordinals must line up with the file-internal occurrence index that
      // `replaceOneOccurrence` uses, so count every range even when a line
      // holds several matches.
      var ordinal = 0;
      for (final match in file.matches) {
        for (var i = 0; i < match.ranges.length; i++) {
          flat.add((
            filePath: file.filePath,
            match: match,
            rangeIndex: i,
            ordinal: ordinal,
          ));
          ordinal++;
        }
      }
    }
    return flat;
  }
}

final searchRunnerProvider = StateNotifierProvider<SearchRunner, SearchState>((
  ref,
) {
  return SearchRunner(ref);
});

/// In-memory matching runs inline below this much total content; anything
/// larger is matched inside a background isolate so typing and toggling match
/// options never janks the UI.
const int _matchIsolateThreshold = 1 << 20; // 1 MiB

/// Upper bound on the retained scan snapshot.
///
/// The cache exists so toggling an option never re-reads the disk, which is
/// worth a lot on a normal project and nothing at all on a huge one: past this
/// point the strings would pin hundreds of megabytes for the life of the
/// process, so the scan is simply re-run instead.
const int _maxCachedBytes = 64 << 20; // 64 MiB

/// Isolate entry point: top-level so it captures nothing.
List<FileSearchResult> _matchFilesEntry(
  (List<ScannedFile>, SearchOptions) args,
) => matchFiles(args.$1, args.$2);

class SearchRunner extends StateNotifier<SearchState> {
  SearchRunner(this.ref) : super(const SearchState());

  final Ref ref;
  SearchCancelToken? _token;

  /// Last completed project scan, reused so option toggles and keystrokes only
  /// re-match in memory. Only written when a scan finished uncancelled.
  ({Directory root, List<ScannedFile> files})? _cache;

  /// Searches [root] for the current [SearchOptions].
  ///
  /// With a valid cache (same root, [rescan] false) this is a pure in-memory
  /// re-match published directly — no disk access, no "running" flicker, which
  /// is what keeps mode toggles instant. Otherwise the project is rescanned
  /// while the previous results stay visible.
  void runSearch(Directory? root, {bool rescan = false}) {
    if (root == null) {
      state = const SearchState(status: SearchStatus.idle);
      return;
    }
    final options = ref.read(searchOptionsProvider);
    if (options.isEmpty) {
      state = const SearchState();
      return;
    }

    _token?.cancelled = true;
    final token = SearchCancelToken();
    _token = token;

    final cache = _cache;
    final reuseCache = !rescan && cache != null && cache.root.path == root.path;

    if (reuseCache) {
      () async {
        try {
          final results = await _matchOffscreen(cache.files, options);
          if (!mounted || token.cancelled) return;
          _publishResults(results);
        } catch (e) {
          if (!mounted) return;
          state = state.copyWith(
            status: SearchStatus.error,
            error: e.toString(),
          );
        }
      }();
      return;
    }

    // Slow path: keep the old results on screen while walking the disk.
    state = state.copyWith(status: SearchStatus.running);

    () async {
      try {
        final files = await scanProject(
          root,
          cancel: token,
          onProgress: (scanned, total) {
            if (!mounted) return;
            state = state.copyWith(scanned: scanned, total: total);
          },
        );
        if (!mounted) return;
        if (token.cancelled) {
          state = state.copyWith(status: SearchStatus.cancelled);
          return;
        }
        var cachedBytes = 0;
        for (final file in files) {
          cachedBytes += file.content.length;
        }
        _cache = cachedBytes <= _maxCachedBytes
            ? (root: root, files: files)
            : null;

        final results = await _matchOffscreen(files, options);
        if (!mounted || token.cancelled) return;
        _publishResults(results);
      } catch (e) {
        if (!mounted) return;
        state = state.copyWith(status: SearchStatus.error, error: e.toString());
      }
    }();
  }

  void cancel() => _token?.cancelled = true;

  /// Resets the panel to its empty/initial state (e.g. when the query is
  /// cleared). The scan cache is deliberately kept so the next search is
  /// instant.
  void clear() => state = const SearchState();

  /// Moves the current-match cursor by [delta] (wraps around) and returns the
  /// occurrence it landed on, or null when there is nothing to navigate.
  FlatSearchMatch? moveCurrent(int delta) {
    final matches = state.flatMatches;
    if (matches.isEmpty) return null;
    final count = matches.length;
    var next = state.currentMatchIndex + delta;
    next %= count;
    if (next < 0) next += count;
    state = state.copyWith(currentMatchIndex: next);
    return matches[next];
  }

  /// Points the current-match cursor at [index] (e.g. a tapped result row).
  void setCurrent(int index) {
    final matches = state.flatMatches;
    if (index < 0 || index >= matches.length) return;
    state = state.copyWith(currentMatchIndex: index);
  }

  /// Replaces only the current match occurrence and refreshes that single
  /// file in the cache and results. Returns whether a replacement was written.
  Future<bool> replaceCurrent(Directory? root) async {
    final matches = state.flatMatches;
    if (matches.isEmpty) return false;
    final index = state.currentMatchIndex.clamp(0, matches.length - 1);
    final current = matches[index];
    final options = ref.read(searchOptionsProvider);
    if (options.isEmpty) return false;

    final replaced = await replaceOneOccurrence(
      current.filePath,
      options,
      current.ordinal,
    );
    if (!replaced || !mounted) return replaced;

    await _refreshFileInResults(current.filePath, options);
    return true;
  }

  /// Writes the replacement text into every file that currently holds matches.
  /// Returns the number of replacements made.
  Future<int> replaceAll(Directory? root) async {
    if (root == null || state.results.isEmpty) return 0;
    final options = ref.read(searchOptionsProvider);
    if (options.isEmpty) return 0;

    final token = SearchCancelToken();
    _token = token;

    final replaced = await replaceAllInResults(
      state.results,
      options,
      cancel: token,
    );

    if (mounted) {
      state = state.copyWith(replaceCount: state.replaceCount + replaced);
    }
    return replaced;
  }

  Future<List<FileSearchResult>> _matchOffscreen(
    List<ScannedFile> files,
    SearchOptions options,
  ) {
    var totalLength = 0;
    for (final file in files) {
      totalLength += file.content.length;
    }
    if (totalLength < _matchIsolateThreshold) {
      return Future.value(matchFiles(files, options));
    }
    return compute(_matchFilesEntry, (files, options));
  }

  void _publishResults(List<FileSearchResult> results) {
    var matchedLines = 0;
    var occurrences = 0;
    for (final result in results) {
      matchedLines += result.matchCount;
      for (final match in result.matches) {
        occurrences += match.ranges.length;
      }
    }
    var current = state.currentMatchIndex;
    if (current >= occurrences) {
      current = occurrences > 0 ? occurrences - 1 : 0;
    }
    state = state.copyWith(
      status: SearchStatus.done,
      results: results,
      matchedFiles: results.length,
      matchedLines: matchedLines,
      currentMatchIndex: current,
    );
  }

  /// Re-reads one file from disk, updates the scan cache entry, and re-matches
  /// just that file so a single replacement doesn't rescan the whole project.
  Future<void> _refreshFileInResults(
    String filePath,
    SearchOptions options,
  ) async {
    final cache = _cache;
    if (cache == null) return;

    String content;
    try {
      content = await File(filePath).readAsString();
    } catch (_) {
      return;
    }
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final updated = <ScannedFile>[];
    for (final file in cache.files) {
      updated.add(
        file.path == filePath ? (path: filePath, content: normalized) : file,
      );
    }
    _cache = (root: cache.root, files: updated);

    final rematched = matchFiles([
      (path: filePath, content: normalized),
    ], options);
    final results = <FileSearchResult>[];
    var replacedEntry = false;
    for (final result in state.results) {
      if (result.filePath == filePath) {
        replacedEntry = true;
        if (rematched.isNotEmpty) results.add(rematched.first);
      } else {
        results.add(result);
      }
    }
    if (!replacedEntry && rematched.isNotEmpty) {
      results.add(rematched.first);
    }

    if (mounted) _publishResults(results);
  }
}
