import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_adapter.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/pylsp_lsp_server.dart';

/// Picks the adapter that serves one launch: data-plugin profiles first
/// (deterministically by server id), then the built-in pylsp server, which is
/// also the fallback because it matches every launch.
class LspServerRegistry {
  const LspServerRegistry({this.contributed = const []});

  /// Adapters built from `DataRegistry` LSP server contributions.
  final List<LspServerAdapter> contributed;

  static const List<LspServerAdapter> builtIns = [PylspLspServerAdapter()];

  /// Adapter serving [context]; never null because the fallback adapter
  /// matches every launch.
  LspServerAdapter resolve(LspServerContext context) {
    final orderedContributed = [...contributed]
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final adapter in [...orderedContributed, ...builtIns]) {
      if (adapter.matches(context)) return adapter;
    }
    return const PylspLspServerAdapter();
  }
}
