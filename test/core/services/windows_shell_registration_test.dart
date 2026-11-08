import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/windows_shell_registration.dart';

void main() {
  const executable = r'C:\Apps\Pyrite IDE\pyrite_ide.exe';
  const command = '"$executable" "%1"';

  late List<List<String>> calls;
  late Map<String, String> registry;
  var failWrites = false;

  setUp(() {
    calls = [];
    registry = {};
    failWrites = false;
  });

  Future<ProcessResult> fakeReg(String exe, List<String> args) async {
    calls.add(args);
    if (args.first == 'query') {
      final value = registry[args[1]];
      return value == null
          ? ProcessResult(0, 1, '', 'not found')
          : ProcessResult(0, 0, '    (Default)    REG_SZ    $value\r\n', '');
    }
    if (failWrites) return ProcessResult(0, 1, '', 'Access is denied');
    if (args.contains('/ve')) registry[args[1]] = args[args.indexOf('/d') + 1];
    return ProcessResult(0, 0, '', '');
  }

  WindowsShellRegistration build() =>
      WindowsShellRegistration(run: fakeReg, executable: executable);

  List<List<String>> writes() =>
      calls.where((call) => call.first == 'add').toList();

  test('registers the link scheme and the package type', () async {
    await build().ensureRegistered();

    expect(
      registry[r'HKCU\Software\Classes\pyride\shell\open\command'],
      command,
    );
    expect(
      registry[r'HKCU\Software\Classes\PyriteIDE.PluginPackage\shell\open\command'],
      command,
    );
    expect(
      registry[r'HKCU\Software\Classes\.pyrix'],
      'PyriteIDE.PluginPackage',
    );
  });

  test('marks pyride as a URL protocol', () async {
    await build().ensureRegistered();

    expect(
      writes().any(
        (call) =>
            call.contains('URL Protocol') &&
            call.contains(r'HKCU\Software\Classes\pyride'),
      ),
      isTrue,
    );
  });

  test('writes only under the current user hive', () async {
    await build().ensureRegistered();

    expect(writes().every((call) => call[1].startsWith(r'HKCU\')), isTrue);
  });

  test('does nothing when already registered for this executable', () async {
    await build().ensureRegistered();
    calls.clear();

    await build().ensureRegistered();

    expect(writes(), isEmpty);
  });

  test('registers again when the install moved', () async {
    await WindowsShellRegistration(
      run: fakeReg,
      executable: r'C:\Old\pyrite_ide.exe',
    ).ensureRegistered();
    calls.clear();

    await build().ensureRegistered();

    expect(writes(), isNotEmpty);
    expect(
      registry[r'HKCU\Software\Classes\pyride\shell\open\command'],
      command,
    );
  });

  test('never throws when the registry refuses writes', () async {
    failWrites = true;

    await expectLater(build().ensureRegistered(), completes);
  });
}
