import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_adapter.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';

/// Translates the BasedPyright strictness level into Zuban's
/// `typeCheckingMode`, which only accepts `auto`, `off`, `default`, or `mypy`.
///
/// Zuban has no strictness ladder in its LSP options — finer control lives in
/// the workspace's zuban/mypy configuration — so every level above "off"
/// collapses to its default mode.
String zubanTypeCheckingMode(BasedPyrightTypeCheckingMode mode) =>
    mode == BasedPyrightTypeCheckingMode.off ? 'off' : 'default';

/// Adapter for the Zuban language server.
///
/// Zuban only speaks stdio, so the executable — and any module-style argument
/// such as `python -m zuban` — is enough to identify it. Detecting the server
/// from the launch keeps the choice out of the settings UI: the user already
/// selects the server by pointing the stdio executable at it.
///
/// Zuban reads one flat options object — no `pylsp`/`basedpyright` sections —
/// and resolves stub paths from the environment (`MYPYPATH`) rather than a
/// configuration key.
class ZubanLspServerAdapter extends LspServerAdapter {
  const ZubanLspServerAdapter();

  @override
  String get id => 'zuban';

  @override
  String get label => 'Zuban';

  @override
  bool matches(LspServerContext context) {
    // Zuban has no WebSocket transport, so only a stdio launch can be one.
    return context.transport == LspType.stdio &&
        context.stdioCommandTokens.any(_isZubanBinaryName);
  }

  @override
  Map<String, dynamic> buildConfiguration(LspServerContext context) => {
    'typeCheckingMode': zubanTypeCheckingMode(context.typeCheckingMode),
    if (context.pythonInterpreter.isNotEmpty)
      'pythonExecutable': context.pythonInterpreter,
    // Check the whole workspace so imported stub modules are covered, not
    // only the files the user happens to have open.
    if (context.stubsEnabled) 'diagnosticMode': 'workspace',
  };

  @override
  Map<String, String> buildEnvironment(
    LspServerContext context,
    Map<String, String> baseEnvironment,
  ) {
    if (!context.stubsEnabled || context.stubsPaths.isEmpty) return const {};
    final existing = baseEnvironment['MYPYPATH'];
    return {
      'MYPYPATH': [
        ...context.stubsPaths,
        if (existing != null && existing.isNotEmpty) existing,
      ].join(Platform.isWindows ? ';' : ':'),
    };
  }
}

/// Whether [name] is the Zuban binary, either bare or at the end of a path
/// such as `C:/tools/zuban.exe`.
bool _isZubanBinaryName(String name) {
  final base = path.basename(name.trim().toLowerCase());
  return base == 'zuban' || base == 'zuban.exe';
}
