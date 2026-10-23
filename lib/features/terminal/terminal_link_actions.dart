/// Opening a link found in terminal output without adding a URL-launcher
/// dependency.
///
/// The project already ships `open_file`, but that package's purpose is
/// revealing files and it routes URLs through platform-specific plugins; using
/// it here would add behaviour we cannot test. Spawning the platform's own
/// opener is one function, works on all three desktop targets the terminal
/// supports, and — because the command is derived by a pure function — is
/// unit-testable.
///
/// The fallback when spawning fails is to copy the URL and tell the user.
/// Failing silently would leave a clickable link that appears dead, and a
/// terminal is exactly where a user copies URLs by hand anyway.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:pyrite_ide/core/i18n/i18n_key.dart';

/// Restricts what a terminal print can hand to the OS.
///
/// Only `http`/`https` are accepted: terminal output is attacker-influenced in
/// the same way any shell output is, and passing an arbitrary scheme to the
/// system opener turns one stray `file:///` or custom-protocol print into a
/// command the user never asked for.
bool isSafeTerminalUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  // A URL without a host is either malformed or an opaque form we cannot open.
  return uri.host.isNotEmpty && !url.contains(RegExp(r'[\x00-\x1f]'));
}

/// The command that asks the OS to open [url] in the default browser.
///
/// Returns null for an unsupported platform so the caller falls back to
/// copying instead of spawning something arbitrary.
({String executable, List<String> arguments})? urlOpenCommand(
  String url, {
  required bool isMacOS,
  required bool isWindows,
  required bool isLinux,
}) {
  if (!isSafeTerminalUrl(url)) return null;
  if (isMacOS) return (executable: 'open', arguments: [url]);
  if (isWindows) {
    // `cmd /c start` treats a quoted first argument as the window title; the
    // empty title keeps the URL from being swallowed as one.
    return (executable: 'cmd', arguments: ['/c', 'start', '', url]);
  }
  if (isLinux) return (executable: 'xdg-open', arguments: [url]);
  return null;
}

/// Result of trying to open a link, so the caller can choose the message.
enum TerminalUrlOpenResult { opened, copied, rejected, failed }

/// Opens [url] with the platform opener, copying it when that is not possible.
Future<TerminalUrlOpenResult> openTerminalUrl(String url) async {
  final command = urlOpenCommand(
    url,
    isMacOS: Platform.isMacOS,
    isWindows: Platform.isWindows,
    isLinux: Platform.isLinux,
  );
  if (command == null) {
    if (!isSafeTerminalUrl(url)) return TerminalUrlOpenResult.rejected;
    await Clipboard.setData(ClipboardData(text: url));
    return TerminalUrlOpenResult.copied;
  }

  try {
    final process = await Process.start(
      command.executable,
      command.arguments,
      // Detach: `open`/`xdg-open` return immediately, and holding the pipes
      // would keep the terminal's process table pointed at a dead child.
      mode: ProcessStartMode.detached,
    );
    // The exit code is intentionally not awaited: a detached process is not
    // guaranteed to report one, and the opener has already done its job.
    unawaited(process.exitCode.catchError((_) => -1));
    return TerminalUrlOpenResult.opened;
  } on ProcessException {
    await Clipboard.setData(ClipboardData(text: url));
    return TerminalUrlOpenResult.copied;
  }
}

/// Maps a link-open outcome onto the message shown to the user.
///
/// Returning null for a successful open keeps the UI quiet in the common case;
/// only the outcomes that need explaining produce a notification.
String? terminalLinkOpenMessage(TerminalUrlOpenResult result) {
  return switch (result) {
    TerminalUrlOpenResult.opened => null,
    TerminalUrlOpenResult.copied => I18nKey.terminalUrlCopied.fallback,
    TerminalUrlOpenResult.rejected => I18nKey.terminalUrlRejected.fallback,
    TerminalUrlOpenResult.failed => I18nKey.terminalUrlOpenFailed.fallback,
  };
}

/// Local `unawaited` so this file does not need `dart:async` just for it.
void unawaited(Future<void> future) {}
