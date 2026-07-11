import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:rfw/formats.dart' show missing;

void main() {
  test('callback register belongs to ui view permission', () {
    expect(Permissions.getRequirement(SdkCommands.callbackRegister), 'ui:view');
  });

  test('callback binding consumes value argument', () {
    final manager = PluginRunManager(port: 1, assetsPath: '.');
    manager.callbackBindings['callback-1-onChanged'] = 'enabled';

    final binding = manager.consumeCallbackBinding(
      'callback-1-onChanged',
      <String, Object?>{'value': true},
    );

    expect(binding?.key, 'enabled');
    expect(binding?.value, true);
    expect(manager.vars['enabled'], true);
  });

  test('callback binding ignores events without returned values', () {
    final manager = PluginRunManager(port: 1, assetsPath: '.');
    manager.callbackBindings['callback-1-onTap'] = 'pressed';

    expect(
      manager.consumeCallbackBinding('callback-1-onTap', <String, Object?>{}),
      isNull,
    );
    expect(
      manager.consumeCallbackBinding('callback-1-onTap', <String, Object?>{
        'value': missing,
      }),
      isNull,
    );
  });

  test(
    'callback binding uses the single returned argument when value is absent',
    () {
      final manager = PluginRunManager(port: 1, assetsPath: '.');
      manager.callbackBindings['callback-1-onTapLink'] = 'url';

      final binding = manager.consumeCallbackBinding(
        'callback-1-onTapLink',
        <String, Object?>{'url': 'https://example.com'},
      );

      expect(binding?.key, 'url');
      expect(binding?.value, 'https://example.com');
    },
  );
}
