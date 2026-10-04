import 'package:pyrite_ide/core/sdk/plugin_transport.dart';

Never _unavailable() => throw StateError(
      'The Python runtime is not available in the web build; plugins are '
      'disabled.',
    );

/// Bootstrap: the web build has no embedded CPython.
Future<void> defaultBootstrapRuntime() => _unavailable();

/// Reset: nothing to reset without a runtime.
Future<void> defaultResetRuntime() async {}

/// Transport factory: unreachable because the bootstrap fails first.
PluginLaunchTransport defaultTransportFactory({
  required String pluginId,
  required String sessionId,
  required bool runOnce,
}) =>
    _unavailable();

/// Program runner: the web build has no embedded CPython.
Future<String?> defaultRunProgram(
  String appPath, {
  required List<String> modulePaths,
  required Map<String, String> environmentVariables,
  required bool sync,
}) =>
    _unavailable();
