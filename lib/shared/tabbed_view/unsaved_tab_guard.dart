// TabData's identity is what the guard keys off, and its `value` field is only
// reachable through tabbed_view's internal file.
// ignore_for_file: implementation_imports

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:tabbed_view/src/tab_data.dart';

/// Whether [tab] holds editor edits that have not reached its backing store.
bool isTabUnsaved(TabData tab) {
  final value = tab.value;
  return value is TabDataValue && !value.isSaved;
}

/// Asks what to do about [tab]'s unsaved edits before it goes away.
///
/// Returns true when the caller may go ahead and close the tab. A clean tab
/// returns true without showing anything; a dirty one prompts, and only save
/// or discard return true — cancelling aborts the close.
///
/// Every close affordance has to route through here. The close button used to
/// prompt while the tab context menu closed silently, so the same file could be
/// kept or dropped depending on which one the user happened to use.
Future<bool> confirmCloseUnsavedTab(BuildContext context, TabData tab) async {
  if (!isTabUnsaved(tab)) return true;

  final container = ProviderScope.containerOf(context);
  final registry = container.read(dataRegistryProvider);
  final locale = container.read(activeLocaleProvider);
  String tr(I18nKey key) => translateFromRegistry(registry, locale, key);

  // The buttons only report the choice; the save and the close both run after
  // the dialog is gone, so nothing acts on a context that has already popped.
  final choice = await showDialog<_UnsavedTabChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr(I18nKey.tabUnsavedDialogTitle)),
      content: Text(tr(I18nKey.tabUnsavedDialogContent)),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UnsavedTabChoice.discard),
          child: Text(tr(I18nKey.tabUnsavedDialogDiscard)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UnsavedTabChoice.save),
          child: Text(tr(I18nKey.tabUnsavedDialogSave)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_UnsavedTabChoice.cancel),
          child: Text(tr(I18nKey.tabUnsavedDialogCancel)),
        ),
      ],
    ),
  );

  switch (choice) {
    case _UnsavedTabChoice.save:
      // Save the tab being closed, not whichever tab is currently selected.
      await container.read(fileProvider.notifier).saveTab(tab);
      container
          .read(ideMessageProvider.notifier)
          .success(tr(I18nKey.tabSavedCurrentFile));
      return true;
    case _UnsavedTabChoice.discard:
      return true;
    case _UnsavedTabChoice.cancel:
    case null:
      return false;
  }
}

enum _UnsavedTabChoice { discard, save, cancel }
