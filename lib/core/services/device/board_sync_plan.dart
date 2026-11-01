import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/device/sync_ignore.dart';

/// What a single planned entry will do during a project sync.
enum BoardSyncAction {
  /// Local file that does not exist on the board yet.
  uploadNew,

  /// Local file is newer / different from the board copy.
  uploadChanged,

  /// Board file that has no local counterpart.
  downloadNew,

  /// Board copy is newer / different from the local file.
  downloadChanged,

  /// Both sides agree; nothing to do.
  unchanged,

  /// Both sides changed and disagree; requires the user's decision.
  conflict,
}

/// Direction a plan entry moves data in.
enum BoardSyncDirection { localToBoard, boardToLocal, none }

/// One file observed on either side.
///
/// `size` and `modified` mirror what the platform/board reports and are
/// nullable because MicroPython's `os.stat` may omit `st_mtime` (many ports
/// return 0 or a tiny epoch) and some virtual filesystems report size 0.
class SyncFileInfo {
  const SyncFileInfo({
    required this.relativePath,
    required this.size,
    this.modified,
  });

  /// Path relative to the sync root, always using `/` separators.
  final String relativePath;

  /// File size in bytes as reported by the host, or `null` when unknown.
  final int? size;

  /// Last modification time, or `null` when the side cannot report one.
  final DateTime? modified;

  /// Whether this side can participate in mtime comparison.
  bool get hasModified =>
      modified != null && modified!.millisecondsSinceEpoch > 0;
}

/// Partition of a project tree into files (with metadata) and directories.
class SyncTreeSnapshot {
  const SyncTreeSnapshot({
    required this.files,
    required this.directories,
    this.root,
  });

  const SyncTreeSnapshot.empty()
    : files = const <String, SyncFileInfo>{},
      directories = const <String>{},
      root = null;

  final Map<String, SyncFileInfo> files;

  /// Relative directory paths (`''` is the root itself, never stored).
  final Set<String> directories;

  final String? root;

  bool get isEmpty => files.isEmpty && directories.isEmpty;
}

/// One line of the sync preview.
class BoardSyncEntry {
  const BoardSyncEntry({
    required this.relativePath,
    required this.action,
    required this.direction,
    this.local,
    this.board,
    this.selectable = true,
    this.ignoredByDefault = false,
    this.note,
  });

  final String relativePath;
  final BoardSyncAction action;
  final BoardSyncDirection direction;

  /// Local metadata, `null` for board-only files.
  final SyncFileInfo? local;

  /// Board metadata, `null` for local-only files.
  final SyncFileInfo? board;

  /// Whether the preview shows a checkbox for this row.
  final bool selectable;

  /// Whether `.pyrsyncignore` covers this path.
  ///
  /// Ignored rows stay in the plan (the user must be able to see what is being
  /// left out and to opt back in), but the preview starts with them unchecked
  /// and folds them into a single collapsed group.
  final bool ignoredByDefault;

  /// Extra explanation shown under the row (e.g. why it is a conflict).
  final String? note;

  bool get isChanged => action != BoardSyncAction.unchanged;

  /// Bytes this entry will move; 0 for unchanged/conflict rows.
  int get transferBytes {
    switch (action) {
      case BoardSyncAction.uploadNew:
      case BoardSyncAction.uploadChanged:
        return local?.size ?? 0;
      case BoardSyncAction.downloadNew:
      case BoardSyncAction.downloadChanged:
        return board?.size ?? 0;
      case BoardSyncAction.unchanged:
      case BoardSyncAction.conflict:
        return 0;
    }
  }

  /// Returns a copy with a different [action] (used when the user overrides a
  /// conflict in the preview) or a different [ignoredByDefault] flag (used when
  /// `.pyrsyncignore` is applied to a freshly built entry). The direction is
  /// recomputed from the action.
  BoardSyncEntry copyWith({BoardSyncAction? action, bool? ignoredByDefault}) {
    final nextAction = action ?? this.action;
    return BoardSyncEntry(
      relativePath: relativePath,
      action: nextAction,
      direction: _directionFor(nextAction),
      local: local,
      board: board,
      selectable: nextAction != BoardSyncAction.unchanged,
      ignoredByDefault: ignoredByDefault ?? this.ignoredByDefault,
      note: nextAction == this.action ? note : null,
    );
  }
}

BoardSyncDirection _directionFor(BoardSyncAction action) {
  switch (action) {
    case BoardSyncAction.uploadNew:
    case BoardSyncAction.uploadChanged:
      return BoardSyncDirection.localToBoard;
    case BoardSyncAction.downloadNew:
    case BoardSyncAction.downloadChanged:
      return BoardSyncDirection.boardToLocal;
    case BoardSyncAction.unchanged:
    case BoardSyncAction.conflict:
      return BoardSyncDirection.none;
  }
}

/// Immutable diff between a local workspace and the board.
///
/// Pure data: it is produced by [buildSyncPlan] and consumed by the preview UI
/// and the executor, so it can be compared, filtered and unit tested without a
/// device attached.
class BoardSyncPlan {
  const BoardSyncPlan({
    required this.entries,
    this.localRoot,
    this.boardRoot = '/',
  });

  final List<BoardSyncEntry> entries;
  final String? localRoot;
  final String boardRoot;

  /// Entries that would move data with the default selection.
  List<BoardSyncEntry> get actionable => entries
      .where(
        (entry) => entry.isChanged && entry.action != BoardSyncAction.conflict,
      )
      .toList(growable: false);

  /// Rows the preview ticks when it opens.
  ///
  /// Everything actionable except the paths `.pyrsyncignore` covers: those are
  /// still transferable, they just have to be ticked on purpose.
  List<BoardSyncEntry> get defaultSelection => actionable
      .where((entry) => !entry.ignoredByDefault)
      .toList(growable: false);

  /// Rows folded into the `.pyrsyncignore` group, unchanged ones included.
  ///
  /// Unchanged rows carry no work but still explain why a path is listed, so
  /// the group shows the same set the ignore file describes.
  List<BoardSyncEntry> get ignoredEntries =>
      entries.where((entry) => entry.ignoredByDefault).toList(growable: false);

  int get ignoredCount => ignoredEntries.length;

  List<BoardSyncEntry> get conflicts => entries
      .where((entry) => entry.action == BoardSyncAction.conflict)
      .toList(growable: false);

  List<BoardSyncEntry> get uploads => entries
      .where(
        (entry) =>
            entry.action == BoardSyncAction.uploadNew ||
            entry.action == BoardSyncAction.uploadChanged,
      )
      .toList(growable: false);

  List<BoardSyncEntry> get downloads => entries
      .where(
        (entry) =>
            entry.action == BoardSyncAction.downloadNew ||
            entry.action == BoardSyncAction.downloadChanged,
      )
      .toList(growable: false);

  int get uploadCount => uploads.length;
  int get downloadCount => downloads.length;
  int get unchangedCount => entries
      .where((entry) => entry.action == BoardSyncAction.unchanged)
      .length;

  bool get isEmpty => entries.isEmpty;

  bool get hasWork =>
      uploadCount > 0 || downloadCount > 0 || conflicts.isNotEmpty;

  /// Total bytes the whole plan would transfer.
  int get totalTransferBytes =>
      actionable.fold(0, (sum, entry) => sum + entry.transferBytes);

  /// Directory paths that must exist on the board before uploading.
  ///
  /// Derived from local-only directories plus the parents of every upload so
  /// the executor never has to guess. Insertion walks deepest-first, so the
  /// iteration order must not be fed straight to `os.mkdir`, which cannot
  /// create missing parents; sort shallowest-first before creating.
  Set<String> get requiredBoardDirectories =>
      boardDirectoriesForUploads(uploads);

  /// Directory paths that must exist locally before downloading.
  Set<String> get requiredLocalDirectories {
    final result = <String>{};
    for (final entry in downloads) {
      final parent = path.posix.dirname('/${entry.relativePath}');
      var current = parent;
      while (current != '/' && current != '.' && current.isNotEmpty) {
        result.add(current.substring(1));
        current = path.posix.dirname(current);
      }
    }
    return result;
  }

  @override
  String toString() =>
      'BoardSyncPlan(entries=${entries.length}, upload=$uploadCount, '
      'download=$downloadCount, conflict=${conflicts.length})';
}

/// Board directories the given [entries] need before their uploads can start.
///
/// The executor calls this with the rows it is actually about to transfer
/// rather than with the whole plan: rows the user left unticked (including
/// everything `.pyrsyncignore` covers) must not leave empty directories behind
/// on the board.
Set<String> boardDirectoriesForUploads(Iterable<BoardSyncEntry> entries) {
  final result = <String>{};
  for (final entry in entries) {
    if (entry.action != BoardSyncAction.uploadNew &&
        entry.action != BoardSyncAction.uploadChanged) {
      continue;
    }
    final parent = path.posix.dirname('/${entry.relativePath}');
    var current = parent;
    while (current != '/' && current != '.' && current.isNotEmpty) {
      result.add(current.substring(1));
      current = path.posix.dirname(current);
    }
  }
  return result;
}

/// How the caller wants mtime differences treated.
enum SyncTimestampPolicy {
  /// Compare size first, then mtime when both sides report one.
  sizeAndMtime,

  /// Ignore mtime entirely; only size differences are considered changes.
  sizeOnly,
}

/// Tolerance applied to mtime comparisons.
///
/// FAT-flashed boards lose sub-second precision, and an upload round trip adds
/// a little skew, so a difference of up to one second is treated as equal.
const Duration syncMtimeTolerance = Duration(seconds: 1);

/// Builds the diff for one pair of files.
///
/// Pure and side-effect free: this is the core of the feature and is what the
/// unit tests exercise. The rules are:
/// * only on one side -> new (upload/download);
/// * both sides, same size, and mtimes agree within [syncMtimeTolerance] or one
///   side cannot report mtime -> unchanged;
/// * both sides differ, and only one side changed since the last known common
///   state -> that side wins;
/// * both sides differ and neither is clearly newer -> conflict.
///
/// [policy] `sizeOnly` exists for boards whose `os.stat` mtime is unusable.
BoardSyncEntry buildSyncEntry({
  required String relativePath,
  required SyncFileInfo? local,
  required SyncFileInfo? board,
  SyncTimestampPolicy policy = SyncTimestampPolicy.sizeAndMtime,
  DateTime? baseline,
  I18nTranslate? translate,
}) {
  final tr = translate ?? fallbackTranslate;
  if (local == null && board == null) {
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.unchanged,
      direction: BoardSyncDirection.none,
      selectable: false,
    );
  }

  if (local != null && board == null) {
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.uploadNew,
      direction: BoardSyncDirection.localToBoard,
      local: local,
    );
  }

  if (local == null && board != null) {
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.downloadNew,
      direction: BoardSyncDirection.boardToLocal,
      board: board,
    );
  }

  final localInfo = local!;
  final boardInfo = board!;

  if (localInfo.size == boardInfo.size && localInfo.size != null) {
    final bothHaveMtime =
        policy == SyncTimestampPolicy.sizeAndMtime &&
        localInfo.hasModified &&
        boardInfo.hasModified;
    if (!bothHaveMtime ||
        _mtimesAgree(localInfo.modified!, boardInfo.modified!)) {
      return BoardSyncEntry(
        relativePath: relativePath,
        action: BoardSyncAction.unchanged,
        direction: BoardSyncDirection.none,
        local: localInfo,
        board: boardInfo,
        selectable: false,
      );
    }
    // Same size but a different mtime: the content may still be different.
    return _decideByMtime(
      relativePath: relativePath,
      local: localInfo,
      board: boardInfo,
      baseline: baseline,
      reason: tr(I18nKey.devicesSyncReasonSameSize),
      tr: tr,
    );
  }

  return _decideByMtime(
    relativePath: relativePath,
    local: localInfo,
    board: boardInfo,
    baseline: baseline,
    reason: tr(I18nKey.devicesSyncReasonSizeMismatch),
    tr: tr,
  );
}

bool _mtimesAgree(DateTime a, DateTime b) =>
    a.difference(b).abs() <= syncMtimeTolerance;

BoardSyncEntry _decideByMtime({
  required String relativePath,
  required SyncFileInfo local,
  required SyncFileInfo board,
  required DateTime? baseline,
  required String reason,
  required I18nTranslate tr,
}) {
  final localHasMtime = local.hasModified;
  final boardHasMtime = board.hasModified;
  if (!localHasMtime || !boardHasMtime) {
    // Without mtime on both sides we cannot tell which copy is newer. Treat a
    // plain size difference as "local edited" (the common editing direction)
    // and flag it so the preview can explain the assumption.
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.uploadChanged,
      direction: BoardSyncDirection.localToBoard,
      local: local,
      board: board,
      note: tr(I18nKey.devicesSyncNoteMissingMtime, {'reason': reason}),
    );
  }

  final localTime = local.modified!;
  final boardTime = board.modified!;

  if (baseline != null) {
    // Last-known common state: whichever side changed afterwards wins.
    final localChanged =
        localTime.difference(baseline).abs() > syncMtimeTolerance;
    final boardChanged =
        boardTime.difference(baseline).abs() > syncMtimeTolerance;
    if (localChanged && !boardChanged) {
      return BoardSyncEntry(
        relativePath: relativePath,
        action: BoardSyncAction.uploadChanged,
        direction: BoardSyncDirection.localToBoard,
        local: local,
        board: board,
        note: tr(I18nKey.devicesSyncNoteLocalChanged, {'reason': reason}),
      );
    }
    if (boardChanged && !localChanged) {
      return BoardSyncEntry(
        relativePath: relativePath,
        action: BoardSyncAction.downloadChanged,
        direction: BoardSyncDirection.boardToLocal,
        local: local,
        board: board,
        note: tr(I18nKey.devicesSyncNoteBoardChanged, {'reason': reason}),
      );
    }
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.conflict,
      direction: BoardSyncDirection.none,
      local: local,
      board: board,
      note: tr(I18nKey.devicesSyncNoteBothChanged, {'reason': reason}),
    );
  }

  if (_mtimesAgree(localTime, boardTime)) {
    // Same age but different bytes: content differs, direction is unknowable.
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.conflict,
      direction: BoardSyncDirection.none,
      local: local,
      board: board,
      note: tr(I18nKey.devicesSyncNoteMtimeClose, {'reason': reason}),
    );
  }

  if (localTime.isAfter(boardTime)) {
    return BoardSyncEntry(
      relativePath: relativePath,
      action: BoardSyncAction.uploadChanged,
      direction: BoardSyncDirection.localToBoard,
      local: local,
      board: board,
      note: tr(I18nKey.devicesSyncNoteLocalNewer, {'reason': reason}),
    );
  }
  return BoardSyncEntry(
    relativePath: relativePath,
    action: BoardSyncAction.downloadChanged,
    direction: BoardSyncDirection.boardToLocal,
    local: local,
    board: board,
    note: tr(I18nKey.devicesSyncNoteBoardNewer, {'reason': reason}),
  );
}

/// Builds the whole plan from two snapshots.
///
/// Union of both sides, sorted by path so the preview is stable between runs.
/// [direction] restricts the plan to one direction; `both` keeps the full
/// diff, which is what the preview shows before the user chooses.
/// [ignore] only tags rows, it never drops them: the preview needs the ignored
/// paths to render the group that explains what will not be synced.
BoardSyncPlan buildSyncPlan({
  required SyncTreeSnapshot local,
  required SyncTreeSnapshot board,
  SyncTimestampPolicy policy = SyncTimestampPolicy.sizeAndMtime,
  Map<String, DateTime> baselines = const {},
  BoardSyncDirection direction = BoardSyncDirection.none,
  bool includeUnchanged = true,
  SyncIgnoreRules ignore = const SyncIgnoreRules.empty(),
  I18nTranslate? translate,
}) {
  final allPaths = <String>{...local.files.keys, ...board.files.keys}.toList()
    ..sort();

  final entries = <BoardSyncEntry>[];
  for (final relativePath in allPaths) {
    var entry = buildSyncEntry(
      relativePath: relativePath,
      local: local.files[relativePath],
      board: board.files[relativePath],
      policy: policy,
      baseline: baselines[relativePath],
      translate: translate,
    );
    if (ignore.shouldIgnore(relativePath)) {
      entry = entry.copyWith(ignoredByDefault: true);
    }
    if (!includeUnchanged && !entry.isChanged) continue;
    // A one-direction plan keeps unchanged rows (they explain what was
    // compared) but drops every entry that would move data the other way.
    if (direction != BoardSyncDirection.none &&
        entry.direction != BoardSyncDirection.none &&
        entry.direction != direction) {
      continue;
    }
    entries.add(entry);
  }

  return BoardSyncPlan(
    entries: entries,
    localRoot: local.root,
    boardRoot: board.root ?? '/',
  );
}

/// Normalizes a board/local relative path to `/`-separated form without a
/// leading slash, so both snapshots use the same keys.
String normalizeSyncRelativePath(String relativePath) {
  var normalized = relativePath.replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized == '.' || normalized == '/') return '';
  if (normalized.startsWith('/')) normalized = normalized.substring(1);
  return path.posix.normalize(normalized);
}
