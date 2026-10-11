import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';

/// Strategy for one language server: how to recognize a launch and what
/// initialization/workspace configuration and process environment it needs.
///
/// Built-in servers ship as concrete subclasses; data plugins contribute
/// declarative profiles through [LspServerProfileAdapter]. The common
/// configuration pipeline (`buildLspStubsConfig`) owns the shared parts —
/// stubs resolution, virtual environment activation, PYTHONPATH — while the
/// adapter owns everything server-specific.
abstract class LspServerAdapter {
  const LspServerAdapter();

  /// Stable identifier, also used by contributed profiles for revocation.
  String get id;

  /// Human-readable name for logs and diagnostics.
  String get label;

  /// Whether this adapter serves [context].
  bool matches(LspServerContext context);

  /// The `initializationOptions` / `workspace/configuration` payload sent to
  /// the server.
  Map<String, dynamic> buildConfiguration(LspServerContext context);

  /// Extra process-environment entries layered on top of the common ones.
  ///
  /// [baseEnvironment] is what has been built so far (platform environment,
  /// virtual environment activation, PYTHONPATH), so adapters that mirror an
  /// existing variable — such as Zuban extending `MYPYPATH` — can append
  /// instead of clobbering.
  Map<String, String> buildEnvironment(
    LspServerContext context,
    Map<String, String> baseEnvironment,
  ) => const {};
}
