import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_config_store.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

/// Handles `sdk.configuration.get|set|list` for Manifest-declared settings.
class SdkConfiguration {
  SdkConfiguration(this.ref);

  final Ref ref;

  void bind(PluginRunManager manager) {
    manager.registerHandler(
      SdkCommands.configurationGet,
      (envelope, respond) => _handleGet(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.configurationSet,
      (envelope, respond) => _handleSet(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkCommands.configurationList,
      (envelope, respond) => _handleList(manager, envelope, respond),
    );
  }

  Future<void> _handleGet(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final id = payload['id']?.toString();
    if (id == null || id.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing configuration id');
      return;
    }
    try {
      final value = await ref
          .read(pluginConfigStoreProvider)
          .get(manager.pluginId, id);
      respond(
        makeEnvelope(
          type: SdkCommands.responseOk,
          payload: {
            'data': {'id': id, 'value': value},
          },
          replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
        ),
      );
    } catch (error) {
      _error(envelope, respond, 'unknown_configuration', error.toString());
    }
  }

  Future<void> _handleSet(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final id = payload['id']?.toString();
    if (id == null || id.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing configuration id');
      return;
    }
    try {
      final value = await ref
          .read(pluginConfigStoreProvider)
          .set(manager.pluginId, id, payload['value']);
      respond(
        makeEnvelope(
          type: SdkCommands.responseOk,
          payload: {
            'data': {'id': id, 'value': value},
          },
          replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
        ),
      );
    } on ArgumentError catch (error) {
      _error(envelope, respond, 'invalid_value', error.message.toString());
    } catch (error) {
      _error(envelope, respond, 'unknown_configuration', error.toString());
    }
  }

  Future<void> _handleList(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) async {
    final items = await ref
        .read(pluginConfigStoreProvider)
        .list(manager.pluginId);
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': items},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }

  void _error(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String code,
    String message,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseError,
        payload: {'code': code, 'message': message, 'details': null},
        replyTo: (envelope['requestId'] ?? envelope['id']).toString(),
      ),
    );
  }
}

final Provider<SdkConfiguration> sdkConfigurationProvider = Provider(
  SdkConfiguration.new,
);
