import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/environment_notifier_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

/// Answers `sdk.env.get` from the host's cached environment.
///
/// Reads the notifier rather than a `BuildContext`, so a plugin can ask before
/// any of its views are mounted. Change pushes are the broadcaster's job.
class SdkEnv {
  SdkEnv(this.ref);

  final Ref ref;

  void bind(PluginRunManager manager) {
    manager.registerHandler(SdkCommands.envGet, _handleGet);
  }

  void _handleGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {
          'data': ref.read(environmentNotifierProvider).snapshot.toJson(),
        },
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }
}

final sdkEnvProvider = Provider((ref) => SdkEnv(ref));
