import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

class ComponentMethodException implements Exception {
  const ComponentMethodException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => '$code: $message';
}

abstract interface class ComponentMethodHost {
  Future<Object?> invokeComponentMethod(
    String componentId,
    String method,
    Map<String, dynamic> arguments,
  );
}

class ComponentMethodRegistry {
  final Map<String, ComponentMethodHost> _hosts = {};

  void attach(ViewInstanceId instance, ComponentMethodHost host) {
    _hosts[instance.key] = host;
  }

  void detach(ViewInstanceId instance, ComponentMethodHost host) {
    if (identical(_hosts[instance.key], host)) _hosts.remove(instance.key);
  }

  void clearSession(String pluginId, String sessionId) {
    _hosts.removeWhere(
      (_, host) =>
          host is ComponentMethodHostEntry &&
          host.instance.pluginId == pluginId &&
          host.instance.sessionId == sessionId,
    );
  }

  void clearPlugin(String pluginId) {
    _hosts.removeWhere(
      (_, host) =>
          host is ComponentMethodHostEntry &&
          host.instance.pluginId == pluginId,
    );
  }

  void clear() => _hosts.clear();

  Future<Object?> invoke(
    ViewInstanceId instance,
    String componentId,
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final host = _hosts[instance.key];
    if (host == null) {
      throw const ComponentMethodException(
        'view_not_mounted',
        'The target view is not mounted',
      );
    }
    return await host.invokeComponentMethod(componentId, method, arguments);
  }
}

abstract interface class ComponentMethodHostEntry
    implements ComponentMethodHost {
  ViewInstanceId get instance;
}

final componentMethodRegistryProvider = Provider<ComponentMethodRegistry>(
  (ref) => ComponentMethodRegistry(),
);
