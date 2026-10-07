import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

/// How the user resolved an externally modified file.
enum ExternalChangeResolution {
  /// Take the disk's version and drop whatever the buffer held.
  reload,

  /// Keep the buffer; the next save overwrites the disk version.
  keepEditor,

  /// Do nothing yet, leaving the buffer exactly as it is.
  cancel,
}

/// Asks what to do about a file that changed on disk while it was open.
///
/// [onSaveConflict] picks the wording: the save path is about to destroy the
/// disk version, whereas a background check found the divergence and has not
/// written anything yet. Both need the same three-way choice, but the user
/// reads a different situation and the message has to say so.
Future<ExternalChangeResolution?> showExternalChangeDialog(
  Ref ref,
  BuildContext context, {
  required String filePath,
  required bool onSaveConflict,
}) {
  final name = path.basename(filePath);
  final bodyKey = onSaveConflict
      ? I18nKey.editorFileChangedOnDiskSaveBody
      : I18nKey.editorFileChangedOnDiskBody;
  // The locale can change while the dialog is up, so the strings are read
  // through a Consumer rather than from the caller's Ref.
  return showDialog<ExternalChangeResolution>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        title: Text(
          translateForWidget(ref, I18nKey.editorFileChangedOnDiskTitle),
        ),
        content: Text(
          translateForWidget(ref, bodyKey).replaceAll('{path}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ExternalChangeResolution.cancel),
            child: Text(translateForWidget(ref, I18nKey.commonCancel)),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ExternalChangeResolution.keepEditor),
            child: Text(
              translateForWidget(ref, I18nKey.editorFileChangedOnDiskKeep),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(ExternalChangeResolution.reload),
            child: Text(
              translateForWidget(ref, I18nKey.editorFileChangedOnDiskReload),
            ),
          ),
        ],
      ),
    ),
  );
}
