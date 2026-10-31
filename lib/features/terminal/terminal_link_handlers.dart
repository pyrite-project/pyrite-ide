/// What a terminal link click actually does, kept out of the surface so the
/// widget layer does not have to import the editor, file provider and message
/// system just to be rendered.
///
/// The surface exposes the hooks ([DesktopTerminalSurface.onUrlClick] and
/// [DesktopTerminalSurface.onFileReferenceClick]); `function_page.dart` wires
/// these implementations in. That split is also what lets the surface be
/// pumped in a widget test with no Riverpod container and no PTY.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/features/edit_core/lsp_location_dialog.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_actions.dart';
import 'package:pyrite_ide/features/terminal/terminal_link_parser.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';

/// Opens [url] in the platform browser, falling back to the clipboard.
Future<void> openTerminalUrlLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final result = await openTerminalUrl(url);
  if (!context.mounted) return;
  final message = terminalLinkOpenMessage(
    result,
    translate: (key, [replacements = const {}]) =>
        translateInContextWithReplacements(context, key, replacements),
  );
  if (message != null) {
    ref.read(ideMessageProvider.notifier).info(message);
  }
}

/// Opens the file that a printed `path:line` refers to, in an editor tab.
///
/// The reference is resolved against the workspace root because a program
/// prints paths relative to its own cwd, which the IDE never learns. The
/// terminal's 1-based line and column are converted to the editor's 0-based
/// coordinates here, in one place, rather than at every call site.
Future<void> revealTerminalFileLink(
  BuildContext context,
  WidgetRef ref,
  TerminalLink link,
) async {
  final resolved = resolveTerminalLinkPath(
    reference: link.path ?? '',
    exists: (candidate) => File(candidate).existsSync(),
    workspaceRoot: ref.read(fileProvider)?.path,
  );
  if (!context.mounted) return;
  if (resolved == null) {
    ref
        .read(ideMessageProvider.notifier)
        .warning(
          translateInContextWithReplacements(
            context,
            I18nKey.terminalFileNotFound,
            {'path': link.path ?? ''},
          ),
        );
    return;
  }
  await revealLspLocation(
    context,
    ref,
    resolved,
    (link.line ?? 1) - 1,
    (link.column ?? 1) - 1,
  );
}
