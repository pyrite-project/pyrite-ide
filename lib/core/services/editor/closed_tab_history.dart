/// The local file a closed editor tab showed, kept so it can be reopened.
///
/// The buffer is recorded together with the text last written to disk, so an
/// unsaved tab reopens with its edits intact and its modified dot still lit.
class ClosedTabRecord {
  const ClosedTabRecord({
    required this.path,
    required this.text,
    required this.savedText,
    required this.isSaved,
    required this.encoding,
    required this.byteOrderMark,
    required this.caretOffset,
  });

  /// Canonical path of the closed file, the record's identity.
  final String path;

  /// The buffer as it was when the tab closed.
  final String text;

  /// The text last written to (or read from) disk, or null when no baseline
  /// was known.
  final String? savedText;

  /// Whether the tab was clean when it closed.
  final bool isSaved;

  /// Character set the file was decoded with, or null for plain UTF-8.
  final String? encoding;

  /// Whether the file started with a byte order mark for [encoding].
  final bool byteOrderMark;

  /// The caret offset at close time, or null when the controller had no valid
  /// selection.
  final int? caretOffset;
}

/// A bounded, most-recent-first history of closed local file tabs.
///
/// Pure in memory: capturing is the editor notifier's job, reopening is the
/// UI's, and everything this class does is testable without a widget tree.
class ClosedTabHistory {
  ClosedTabHistory({this.maxLength = defaultMaxLength}) : assert(maxLength > 0);

  /// How many records a default history keeps.
  static const int defaultMaxLength = 10;

  /// The most records this history keeps; older ones fall off the end.
  final int maxLength;

  final List<ClosedTabRecord> _records = [];

  /// The records still remembered, newest first.
  List<ClosedTabRecord> get records => List.unmodifiable(_records);

  /// The newest record, or null when nothing has been closed yet.
  ClosedTabRecord? get newest => _records.isEmpty ? null : _records.first;

  bool get isEmpty => _records.isEmpty;

  bool get isNotEmpty => _records.isNotEmpty;

  int get length => _records.length;

  /// Remembers [record] as the newest closed tab.
  ///
  /// A record for a path already in the history replaces the old one instead
  /// of stacking: the history reopens files, and two entries for one path
  /// would make "reopen" appear to pop the same file twice.
  void push(ClosedTabRecord record) {
    _records.removeWhere((existing) => existing.path == record.path);
    _records.insert(0, record);
    if (_records.length > maxLength) {
      _records.removeRange(maxLength, _records.length);
    }
  }

  /// Removes and returns the newest record, or null when there is none.
  ClosedTabRecord? take() => _records.isEmpty ? null : _records.removeAt(0);

  /// Forgets [path], returning whether it was in the history.
  bool remove(String path) {
    final before = _records.length;
    _records.removeWhere((record) => record.path == path);
    return _records.length != before;
  }

  /// Forgets every closed tab.
  void clear() => _records.clear();
}
