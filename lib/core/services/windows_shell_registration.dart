import 'dart:io';

import 'package:flutter/foundation.dart';

const _protocolKey = r'HKCU\Software\Classes\pyride';
const _packageExtensionKey = r'HKCU\Software\Classes\.pyrix';
const _packageTypeKey = r'HKCU\Software\Classes\PyriteIDE.PluginPackage';

typedef RegistryRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Registers `pyride://` links and `.pyrix` files for the current Windows user.
///
/// The Windows build ships as a plain archive with no installer, so the IDE
/// registers itself. Everything lives under HKCU, which needs no elevation and
/// is removed with the user profile; nothing is written when the registered
/// command already points at this executable.
class WindowsShellRegistration {
  WindowsShellRegistration({RegistryRunner? run, String? executable})
    : _run = run ?? Process.run,
      _executable = executable ?? Platform.resolvedExecutable;

  final RegistryRunner _run;
  final String _executable;

  String get _openCommand => '"$_executable" "%1"';

  Future<void> ensureRegistered() async {
    try {
      if (await _registeredCommand(_protocolKey) == _openCommand &&
          await _registeredCommand(_packageTypeKey) == _openCommand) {
        return;
      }
      await _register();
    } on Object catch (error) {
      // A locked-down machine can refuse registry writes; links then simply do
      // not open the IDE, which must not stop it from starting.
      debugPrint('WindowsShellRegistration: $error');
    }
  }

  Future<void> _register() async {
    await _set(_protocolKey, 'URL:Pyrite IDE plugin install');
    await _set(_protocolKey, '', name: 'URL Protocol');
    await _set('$_protocolKey\\DefaultIcon', '"$_executable",0');
    await _set('$_protocolKey\\shell\\open\\command', _openCommand);

    await _set(_packageExtensionKey, 'PyriteIDE.PluginPackage');
    await _set(_packageTypeKey, 'Pyrite IDE plugin package');
    await _set('$_packageTypeKey\\DefaultIcon', '"$_executable",0');
    await _set('$_packageTypeKey\\shell\\open\\command', _openCommand);
  }

  Future<void> _set(String key, String value, {String? name}) async {
    final result = await _run('reg', [
      'add',
      key,
      if (name == null) '/ve' else ...['/v', name],
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('reg', ['add', key], '${result.stderr}');
    }
  }

  Future<String?> _registeredCommand(String key) async {
    final result = await _run('reg', [
      'query',
      '$key\\shell\\open\\command',
      '/ve',
    ]);
    if (result.exitCode != 0) return null;
    final match = RegExp(
      r'REG_SZ\s+(.*)$',
      multiLine: true,
    ).firstMatch('${result.stdout}');
    return match?.group(1)?.trim();
  }
}
