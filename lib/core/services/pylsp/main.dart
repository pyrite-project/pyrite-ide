import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import 'package:pyrite_ide/core/services/file.dart';
import 'package:pyrite_ide/core/services/pylsp/core.dart';
import 'package:pyrite_ide/core/services/pylsp/data.dart';

class LspClientNotifier extends AsyncNotifier<LspClient> {
  @override
  Future<LspClient> build() async {
    final process = await startLspServer();
    final client = LspClient(process);

    ref.onDispose(() => client.close());

    final workspaceDir = ref.read(directory);
    final rootUri = workspaceDir == null
        ? null
        : Uri.directory(workspaceDir.path).toString();
    await client.initialize(rootUri: rootUri);

    client.notifications.listen((notification) {
      if (notification["method"] == "textDocument/publishDiagnostics") {
        final params = notification["params"];
        if (params is Map<String, dynamic>) {
          handleDiagnostics(params);
        }
      }
    });

    return client;
  }
}

final AsyncNotifierProvider<LspClientNotifier, LspClient> lspClientProvider =
    AsyncNotifierProvider<LspClientNotifier, LspClient>(
      () => LspClientNotifier(),
    );

class PythonLspService {
  final dynamic _ref;

  const PythonLspService(this._ref);

  Future<LspClient> get client async {
    final AsyncValue<LspClient> asyncClient = _ref.read(lspClientProvider);

    return asyncClient.when(
      loading: () {
        throw StateError('LSP Client is currently initializing.');
      },
      error: (error, stackTrace) {
        throw error;
      },
      data: (client) {
        return client;
      },
    );
  }
}
