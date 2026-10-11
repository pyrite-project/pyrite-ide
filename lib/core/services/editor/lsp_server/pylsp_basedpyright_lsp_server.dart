import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_adapter.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';
import 'package:pyrite_ide/core/services/editor/python_virtual_environment.dart';

/// Fallback adapter covering the sectioned configuration shared by pylsp and
/// BasedPyright.
///
/// Both servers ignore sections they do not know, so one payload carries the
/// `pylsp` (jedi), `basedpyright`, and `python` sections at once; servers
/// with their own option shape (Zuban) claim the launch before this adapter
/// is consulted.
class PylspBasedPyrightLspServerAdapter extends LspServerAdapter {
  const PylspBasedPyrightLspServerAdapter();

  @override
  String get id => 'pylsp-basedpyright';

  @override
  String get label => 'pylsp / BasedPyright';

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
    final basedPyrightAnalysis = <String, dynamic>{
      'typeCheckingMode': context.typeCheckingMode.jsonName,
      if (context.stubsPaths.isNotEmpty) 'extraPaths': context.stubsPaths,
    };
    final virtualEnvironment = context.virtualEnvironment;
    return {
      if (jediConfiguration.isNotEmpty)
        'pylsp': {
          'plugins': {'jedi': jediConfiguration},
        },
      'basedpyright': {'analysis': basedPyrightAnalysis},
      // Let BasedPyright discover the workspace's .venv with its native
      // handling, preserving virtual-environment paths for uv symlink targets.
      if (virtualEnvironment != null &&
          !isWorkspaceDefaultVirtualEnvironment(
            virtualEnvironment,
            workspacePath: context.workspacePath,
          ))
        'python': {
          'venvPath': virtualEnvironment.root.parent.path,
          'venv': path.basename(virtualEnvironment.root.path),
        },
    };
  }
}
