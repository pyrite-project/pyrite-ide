import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';
import 'package:pyrite_ide/core/sdk/python_runtime_boot.dart';
import 'package:serious_python/serious_python.dart';

/// Extracts the runtime boot assets and boots the embedded interpreter.
Future<void> defaultBootstrapRuntime() async {
  final runtimeDirectory = await extractAssetZip(
    pythonRuntimeBootAsset,
    targetPath: pythonRuntimeBootCachePath,
    checkHash: true,
  );
  final error = await SeriousPython.runProgram(
    path.join(runtimeDirectory, 'boot.py'),
    sync: true,
  );
  if (error != null) throw StateError(error);
}

/// Resets the persistent embedded interpreter.
Future<void> defaultResetRuntime() => SeriousPython.resetRuntime();

/// Creates the native Python-bridge transport for a plugin session.
PluginLaunchTransport defaultTransportFactory({
  required String pluginId,
  required String sessionId,
  required bool runOnce,
}) {
  final suffix = runOnce ? '.once' : '';
  return PythonBridgePluginTransport(
    channelLabel: 'pyrite.plugin.$pluginId.$sessionId$suffix',
  );
}

/// Runs a plugin program inside the embedded interpreter.
Future<String?> defaultRunProgram(
  String appPath, {
  required List<String> modulePaths,
  required Map<String, String> environmentVariables,
  required bool sync,
}) {
  return SeriousPython.runProgram(
    appPath,
    modulePaths: modulePaths,
    environmentVariables: environmentVariables,
    sync: sync,
  );
}
