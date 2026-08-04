import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus.dart';
import 'package:pyrite_ide/core/sdk/plugin_event_bus_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

abstract class SdkEventsCommands {
  static const String subscribe = 'sdk.events.subscribe';
  static const String unsubscribe = 'sdk.events.unsubscribe';
}

/// Binds the event-subscription protocol to a plugin session.
///
/// Subscribe/unsubscribe requests are resolved against the host [PluginEventBus]
/// using the plugin/session identity already validated by the run manager, so a
/// plugin can only manage its own subscriptions.
class SdkEvents {
  SdkEvents(this.ref);

  final Ref ref;

  PluginEventBus get _bus => ref.read(pluginEventBusProvider);

  void bind(PluginRunManager manager) {
    manager.registerHandler(
      SdkEventsCommands.subscribe,
      (envelope, respond) => _handleSubscribe(manager, envelope, respond),
    );
    manager.registerHandler(
      SdkEventsCommands.unsubscribe,
      (envelope, respond) => _handleUnsubscribe(manager, envelope, respond),
    );
  }

  void _handleSubscribe(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final subscriptionId = payload['subscriptionId']?.toString();
    final topic = payload['topic']?.toString();
    if (subscriptionId == null || subscriptionId.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing subscriptionId');
      return;
    }
    if (topic == null || topic.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing topic');
      return;
    }
    final rawFilter = payload['filter'];
    final filter = rawFilter is Map
        ? rawFilter.map((key, value) => MapEntry(key.toString(), value))
        : null;
    final rawDelivery = payload['delivery'];
    final delivery = rawDelivery is Map
        ? EventDeliverySpec.fromJson(
            rawDelivery.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;

    final result = _bus.subscribe(
      subscriptionId: subscriptionId,
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      generation: manager.generation,
      topicName: topic,
      pluginPermissions: manager.pluginPermissions,
      filter: filter,
      delivery: delivery,
    );
    if (result.isOk) {
      _ok(envelope, respond, {'subscriptionId': subscriptionId});
    } else {
      _error(
        envelope,
        respond,
        result.errorCode ?? 'internal_error',
        result.message ?? 'Subscription failed',
      );
    }
  }

  void _handleUnsubscribe(
    PluginRunManager manager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final subscriptionId = payload['subscriptionId']?.toString();
    if (subscriptionId == null || subscriptionId.isEmpty) {
      _error(envelope, respond, 'invalid_request', 'Missing subscriptionId');
      return;
    }
    final removed = _bus.unsubscribe(
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      subscriptionId: subscriptionId,
    );
    _ok(envelope, respond, {'removed': removed});
  }

  void _ok(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    dynamic data,
  ) {
    respond(
      makeEnvelope(
        type: SdkCommands.responseOk,
        payload: {'data': data},
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

final Provider<SdkEvents> sdkEventsProvider = Provider(SdkEvents.new);
