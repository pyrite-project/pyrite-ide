import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_adapter.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';

/// The only built-in server: python-lsp-server (`pylsp`).
///
/// The IDE no longer carries option shapes for individual type checkers.
/// Servers such as BasedPyright or Zuban are described by data plugins through
/// `sdk.lsp.contribute`, so their option keys — flat objects, nested sections,
/// strictness vocabularies — live with the plugin that knows them instead of
/// here.
///
/// pylsp stays built in because it is the default Python language server a
/// fresh install talks to and its payload is the shared jedi configuration.
/// The adapter matches every launch, so it also serves as the fallback for a
/// server no plugin claimed: sending `pylsp` to a server that does not read
/// that section is ignored by protocol, which is safer than sending one
/// server's options to another.
class PylspLspServerAdapter extends LspServerAdapter {
  const PylspLspServerAdapter();

  @override
  String get id => 'pylsp';

  @override
  String get label => 'pylsp';

  @override
  bool matches(LspServerContext context) => true;

  @override
  Map<String, dynamic> buildConfiguration(LspServerContext context) {
    final jediConfiguration = <String, dynamic>{
      if (context.stubsPaths.isNotEmpty) ...{
        'extra_paths': context.stubsPaths,
        'prioritize_extra_paths': true,
      },
      if (context.pythonInterpreter.isNotEmpty)
        'environment': context.pythonInterpreter,
    };
    if (jediConfiguration.isEmpty) return const {};
    return {
      'pylsp': {
        'plugins': {'jedi': jediConfiguration},
      },
    };
  }
}
