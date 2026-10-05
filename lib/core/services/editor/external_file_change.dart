import 'dart:io';

import 'package:pyrite_ide/core/services/editor/file_open_codec.dart';

/// What was on disk for a path the last time the editor looked at it.
///
/// Size alone cannot decide whether a file changed: an edit that replaces
/// "abc" with "xyz" leaves both the length and possibly the mtime granularity
/// untouched. The pair catches the common cases cheaply, and the recorded
/// text settles the rest.
class FileDiskStamp {
  const FileDiskStamp({required this.modified, required this.size});

  final DateTime modified;
  final int size;

  bool sameAs(FileDiskStamp other) =>
      modified == other.modified && size == other.size;

  @override
  bool operator ==(Object other) =>
      other is FileDiskStamp &&
      other.modified == modified &&
      other.size == size;

  @override
  int get hashCode => Object.hash(modified, size);
}

/// Reads the current stamp for [file], or null when it does not exist.
///
/// Windows reports a missing path as a successful stat whose type is
/// `notFound`, with size -1 and a 1970 mtime, rather than throwing the way
/// POSIX does. Trusting only the exception would make every deleted file look
/// like it had changed, so the type is checked as well.
Future<FileDiskStamp?> statFileStamp(File file) async {
  try {
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return FileDiskStamp(modified: stat.modified, size: stat.size);
  } on FileSystemException {
    return null;
  }
}

/// What the editor should do about a path whose bytes moved underneath it.
enum ExternalChangeAction {
  /// Nothing observable changed; refresh the stamp and move on.
  none,

  /// The file was touched but its text is byte-identical to what the editor
  /// last wrote, so there is nothing to reconcile.
  touchOnly,

  /// The file no longer exists. The buffer stays readable but must stop being
  /// written back over a path that is not there.
  deleted,

  /// The file changed and the tab has no unsaved edits, so the disk version
  /// can replace the buffer outright.
  reload,

  /// The file changed while the tab holds unsaved edits. Reloading would throw
  /// the user's work away and keeping the buffer silently discards the other
  /// program's work, so this needs a decision.
  prompt,
}

/// Decides how to reconcile an open tab with what is on disk now.
///
/// Pure so the policy can be tested without touching a filesystem; the caller
/// supplies everything it would otherwise have to read.
ExternalChangeAction planExternalChange({
  required bool exists,
  required FileDiskStamp? previousStamp,
  required FileDiskStamp? currentStamp,
  required String? diskText,
  required String? baseline,
  required bool tabIsDirty,
}) {
  if (!exists) return ExternalChangeAction.deleted;
  // No text to compare against — the file is binary, or unreadable in its own
  // encoding. The stamp moved, which is all we can honestly report.
  if (diskText == null) return ExternalChangeAction.touchOnly;

  // A tab with no recorded baseline is an empty buffer, not a wildcard: a file
  // that is also empty has genuinely not diverged from it.
  final effectiveBaseline = baseline ?? '';
  if (diskText == effectiveBaseline) {
    // Content matches what we last wrote. A differing stamp is a touch, a
    // same-length rewrite, or a tool that rewrote the file unchanged.
    return previousStamp != null &&
            currentStamp != null &&
            !previousStamp.sameAs(currentStamp)
        ? ExternalChangeAction.touchOnly
        : ExternalChangeAction.none;
  }

  // Content genuinely differs from our baseline. A dirty tab means the user
  // has edits of their own that a reload would destroy.
  return tabIsDirty ? ExternalChangeAction.prompt : ExternalChangeAction.reload;
}

/// Reads [file] and returns the text to compare against a baseline.
///
/// Returns null when the bytes cannot be decoded — a binary file, or text in
/// an encoding the open flow would have asked about. Reporting "no text" keeps
/// the caller from reloading a buffer with a malformed decode of the whole
/// file.
Future<String?> readDiskText(File file) async {
  try {
    final prepared = await prepareFileForEditing(file);
    return switch (prepared) {
      TextFilePrepared(:final text) => text,
      LargeFilePrepared(:final text) => text,
      UndecodableFilePrepared() || BinaryFilePrepared() => null,
    };
  } on FileSystemException {
    return null;
  }
}
