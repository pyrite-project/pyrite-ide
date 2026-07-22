import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/services/file/upload_and_download_diff.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/shared/studio_text.dart';

void showEditorSnackBar(BuildContext context, String message) {
  showIdeSuccess(context, message);
}

/// Shows a prominent Thonny-style dialog when the device is not in REPL state.
/// Returns true if the user chose to send CTRL-C, false if dismissed.
Future<bool> showDeviceNotReadyDialog(
  BuildContext context, {
  required String operation,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const UseText(I18nKey.dialogDeviceNotReadyTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogDeviceNotReadyOperation,
              ).replaceAll('{operation}', operation),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: UseText(
                I18nKey.dialogDeviceNotReadyReason,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const UseText(
              I18nKey.dialogDeviceNotReadyHint,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const UseText(I18nKey.dialogSendCtrlC),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

Future<bool> showDiffConfirmDialog(
  BuildContext context, {
  required DiffInfo diff,
  required String targetPath,
  required bool isUpload,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final action = translateForWidget(
          ref,
          isUpload ? I18nKey.dialogUploadAction : I18nKey.dialogDownloadAction,
        );
        return AlertDialog(
          icon: const Icon(Icons.difference),
          title: UseText(
            isUpload
                ? I18nKey.dialogConfirmUpload
                : I18nKey.dialogConfirmDownload,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translateForWidget(ref, I18nKey.dialogDiffTarget)
                    .replaceAll('{action}', action)
                    .replaceAll('{path}', targetPath),
              ),
              const SizedBox(height: 8),
              Text(
                translateForWidget(ref, I18nKey.dialogDiffSummary)
                    .replaceAll('{add}', diff.addCount.toString())
                    .replaceAll('{remove}', diff.removeCount.toString()),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      diff.unifiedLines.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const UseText(I18nKey.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: UseText(
                isUpload
                    ? I18nKey.dialogUploadAction
                    : I18nKey.dialogDownloadAction,
              ),
            ),
          ],
        );
      },
    ),
  );
  return result ?? false;
}

enum FileConflictAction {
  overwrite,
  skip,
  overwriteAll,
  skipAll,
  showDiff,
  cancel,
}

Future<FileConflictAction> showFileConflictDialog(
  BuildContext context, {
  required String sourcePath,
  required String targetPath,
  required bool isUpload,
  bool canShowDiff = false,
}) async {
  final result = await showDialog<FileConflictAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: UseText(
          isUpload
              ? I18nKey.dialogUploadConflict
              : I18nKey.dialogDownloadConflict,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogConflictTarget,
              ).replaceAll('{path}', targetPath),
            ),
            const SizedBox(height: 8),
            Text(
              translateForWidget(
                ref,
                I18nKey.dialogConflictSource,
              ).replaceAll('{path}', sourcePath),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.cancel),
            child: const UseText(I18nKey.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.skip),
            child: const UseText(I18nKey.dialogSkip),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.skipAll),
            child: const UseText(I18nKey.dialogSkipAll),
          ),
          if (canShowDiff)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, FileConflictAction.showDiff),
              icon: const Icon(Icons.difference, size: 18),
              label: const UseText(I18nKey.dialogShowDiff),
            ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, FileConflictAction.overwriteAll),
            child: const UseText(I18nKey.dialogOverwriteAll),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, FileConflictAction.overwrite),
            child: const UseText(I18nKey.dialogOverwrite),
          ),
        ],
      ),
    ),
  );
  return result ?? FileConflictAction.cancel;
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const UseText(I18nKey.dialogDeleteItemTitle),
        content: Text(
          translateForWidget(
            ref,
            I18nKey.dialogDeleteItemMessage,
          ).replaceAll('{name}', name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const UseText(I18nKey.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const UseText(I18nKey.fileActionDelete),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
