import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:rfw/formats.dart' show missing;

void main() {
  test('callback register belongs to ui view permission', () {
    expect(Permissions.getRequirement(SdkCommands.callbackRegister), 'ui:view');
    expect(Permissions.getRequirement(SdkCommands.callbackSet), 'ui:view');
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

  test('callback is not sent when SDK does not require it', () async {
    final manager = PluginRunManager(port: 1, assetsPath: '.');

    await manager.sendCallback('callback-1-onChanged', <String, Object?>{
      'value': true,
    }, 'home');
  });

  test('callback list received over websocket enables IDE callback', () async {
    const callbackName = 'callback-1-onPressed';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final callbackSet = Completer<void>();
    final callbackSent = Completer<Map<String, dynamic>>();
    final manager = PluginRunManager(port: server.port, assetsPath: '.');

    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((message) {
        final envelope = jsonDecode(message as String) as Map<String, dynamic>;
        if (envelope['type'] == SdkCommands.responseOk) {
          callbackSet.complete();
        } else if (envelope['type'] == IdeCommands.eventCallback) {
          callbackSent.complete(envelope);
        }
      });
      socket.add(
        jsonEncode(
          makeEnvelope(
            type: SdkCommands.callbackSet,
            payload: {
              'callbacks': [callbackName],
            },
          ),
        ),
      );
    });

    try {
      await manager.connect();
      await callbackSet.future.timeout(const Duration(seconds: 2));
      await manager.sendCallback(callbackName, <String, Object?>{}, 'home');

      final envelope = await callbackSent.future.timeout(
        const Duration(seconds: 2),
      );
      expect(envelope['payload']['name'], callbackName);
    } finally {
      await manager.stop();
      await server.close(force: true);
    }
  });
}
