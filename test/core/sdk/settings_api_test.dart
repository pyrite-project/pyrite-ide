import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/settings_api.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class _SettingsHarness {
  _SettingsHarness._();

  final ProviderContainer container = ProviderContainer();
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();

  late final HttpServer server;
  late final PluginRunManager manager;
  late final WebSocket socket;
  late final StreamSubscription<WebSocket> _serverSubscription;
  StreamSubscription<dynamic>? _socketSubscription;

  static Future<_SettingsHarness> start({
    Map<String, List<String>> permissions = const {
      'settings': ['read', 'write'],
    },
  }) async {
    final harness = _SettingsHarness._();
    harness.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    final socketReady = Completer<WebSocket>();
    harness._serverSubscription = harness.server
        .transform(WebSocketTransformer())
        .listen((socket) {
          harness._socketSubscription = socket.listen((message) {
            harness._responses.add(
              jsonDecode(message as String) as Map<String, dynamic>,
            );
          });
          if (!socketReady.isCompleted) {
            socketReady.complete(socket);
          }
        });

    harness.manager = PluginRunManager(
      port: harness.server.port,
      assetsPath: '.',
      pluginId: 'settings-test',
      pluginPermissions: permissions,
    );
    harness.container.read(sdkSettingsProvider.notifier).bind(harness.manager);

    await harness.manager.connect();
    harness.socket = await socketReady.future.timeout(
      const Duration(seconds: 5),
    );
    return harness;
  }

  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final envelope = makeEnvelope(type: type, payload: payload);
    final response = _responses.stream
        .firstWhere((item) => item['reply_to'] == envelope['id'])
        .timeout(const Duration(seconds: 5));
    socket.add(jsonEncode(envelope));
    return response;
  }

  Future<Map<String, dynamic>> get(String name) {
    return request(SdkSettingsCommands.get, payload: {'name': name});
  }

  Future<Map<String, dynamic>> set(String name, dynamic value) {
    return request(
      SdkSettingsCommands.set,
      payload: {'name': name, 'value': value},
    );
  }

  Future<Map<String, dynamic>> list() {
    return request(SdkSettingsCommands.list);
  }

  Future<void> close() async {
    await manager.stop();
    await _socketSubscription?.cancel();
    await socket.close();
    await _serverSubscription.cancel();
    await server.close(force: true);
    await _responses.close();
    container.dispose();
  }
}

void _expectOk(Map<String, dynamic> response, dynamic data) {
  expect(response['type'], SdkCommands.responseOk);
  expect(response['payload'], {'data': data});
  expect(response['reply_to'], isNotEmpty);
}

void _expectSettingError(Map<String, dynamic> response, String message) {
  expect(response['type'], SdkCommands.responseError);
  expect(response['payload']['message'], contains('设置失败'));
  expect(response['payload']['message'], contains(message));
}

void main() {
  test('settings commands use the existing read and write permissions', () {
    expect(
      Permissions.getRequirement(SdkSettingsCommands.get),
      'settings:read',
    );
    expect(
      Permissions.getRequirement(SdkSettingsCommands.list),
      'settings:read',
    );
    expect(
      Permissions.getRequirement(SdkSettingsCommands.set),
      'settings:write',
    );
    expect(
      Permissions.check(const {
        'settings': ['write'],
      }, 'settings:read'),
      isTrue,
    );
  });

  test('theme settings set, get, and list over websocket', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);
    harness.container
        .read(dataRegistryProvider)
        .registerTheme('fixture', 'nord', const {});

    final listResponse = await harness.list();
    expect(listResponse['type'], SdkCommands.responseOk);
    final settings = listResponse['payload']['data'] as List<dynamic>;
    final settingsByName = <String, String>{
      for (final item in settings.whereType<Map>())
        item['name'].toString(): item['type'].toString(),
    };
    expect(settingsByName, containsPair('theme.mode', 'string'));
    expect(settingsByName, containsPair('theme.style', 'string'));
    expect(settingsByName, containsPair('theme.color', 'int'));
    expect(
      settingsByName,
      containsPair('theme.active_plugin_theme_id', 'string'),
    );
    expect(
      settingsByName,
      containsPair('theme.use_material_context_menu', 'bool'),
    );

    _expectOk(await harness.set('theme.mode', 'dark'), true);
    _expectOk(await harness.set('theme.style', 'compact'), true);
    _expectOk(await harness.set('theme.color', 0xff336699), true);
    _expectOk(
      await harness.set('theme.active_plugin_theme_id', 'fixture::nord'),
      true,
    );
    _expectOk(await harness.set('theme.use_material_context_menu', true), true);

    expect(harness.container.read(themeMode), ThemeMode.dark);
    expect(harness.container.read(themeStyle), ThemeStyle.compact);
    expect(harness.container.read(themeColor)?.toARGB32(), 0xff336699);
    expect(harness.container.read(activePluginThemeId), 'fixture::nord');
    expect(harness.container.read(useMaterialContextMenu), isTrue);

    _expectOk(await harness.get('theme.mode'), {
      'name': 'theme.mode',
      'value': 'dark',
    });
    _expectOk(await harness.get('theme.style'), {
      'name': 'theme.style',
      'value': 'compact',
    });
    _expectOk(await harness.get('theme.color'), {
      'name': 'theme.color',
      'value': 0xff336699,
    });
    _expectOk(await harness.get('theme.active_plugin_theme_id'), {
      'name': 'theme.active_plugin_theme_id',
      'value': 'fixture::nord',
    });
    _expectOk(await harness.get('theme.use_material_context_menu'), {
      'name': 'theme.use_material_context_menu',
      'value': true,
    });
  });

  test('nullable theme settings can be cleared', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);
    harness.container
        .read(dataRegistryProvider)
        .registerTheme('fixture', 'nord', const {});

    _expectOk(await harness.set('theme.color', 0xff008577), true);
    _expectOk(
      await harness.set('theme.active_plugin_theme_id', 'fixture::nord'),
      true,
    );
    _expectOk(await harness.set('theme.color', null), true);
    _expectOk(await harness.set('theme.active_plugin_theme_id', null), true);

    expect(harness.container.read(themeColor), isNull);
    expect(harness.container.read(activePluginThemeId), isNull);
    _expectOk(await harness.get('theme.color'), {
      'name': 'theme.color',
      'value': null,
    });
    _expectOk(await harness.get('theme.active_plugin_theme_id'), {
      'name': 'theme.active_plugin_theme_id',
      'value': null,
    });
  });

  test('invalid theme values return errors without changing state', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);
    harness.container
        .read(dataRegistryProvider)
        .registerTheme('fixture', 'nord', const {});

    _expectOk(await harness.set('theme.mode', 'light'), true);
    _expectOk(await harness.set('theme.style', 'comfortable'), true);
    _expectOk(await harness.set('theme.color', 0xff123456), true);
    _expectOk(
      await harness.set('theme.active_plugin_theme_id', 'fixture::nord'),
      true,
    );

    _expectSettingError(
      await harness.set('theme.mode', 'sepia'),
      'Expected system, light, or dark',
    );
    _expectSettingError(
      await harness.set('theme.style', 'dense'),
      'Expected standard, compact, or comfortable',
    );
    _expectSettingError(
      await harness.set('theme.color', '#123456'),
      'Expected an ARGB32 integer between 0 and 0xFFFFFFFF, or null',
    );
    _expectSettingError(
      await harness.set('theme.color', -1),
      'Expected an ARGB32 integer between 0 and 0xFFFFFFFF, or null',
    );
    _expectSettingError(
      await harness.set('theme.color', 0x100000000),
      'Expected an ARGB32 integer between 0 and 0xFFFFFFFF, or null',
    );
    _expectSettingError(
      await harness.set('theme.active_plugin_theme_id', 'missing::theme'),
      'Unknown plugin theme',
    );
    _expectSettingError(
      await harness.set('theme.use_material_context_menu', 'true'),
      'Expected a boolean',
    );

    expect(harness.container.read(themeMode), ThemeMode.light);
    expect(harness.container.read(themeStyle), ThemeStyle.comfortable);
    expect(harness.container.read(themeColor)?.toARGB32(), 0xff123456);
    expect(harness.container.read(activePluginThemeId), 'fixture::nord');
    expect(harness.container.read(useMaterialContextMenu), isFalse);
  });

  test('read-only settings permission denies set over websocket', () async {
    final harness = await _SettingsHarness.start(
      permissions: const {
        'settings': ['read'],
      },
    );
    addTearDown(harness.close);

    _expectOk(await harness.get('theme.mode'), {
      'name': 'theme.mode',
      'value': 'system',
    });
    expect((await harness.list())['type'], SdkCommands.responseOk);

    final denied = await harness.set('theme.mode', 'dark');
    expect(denied['type'], IdeCommands.responseError);
    expect(denied['payload']['message'], 'Permission denied: settings:write');
    expect(harness.container.read(themeMode), ThemeMode.system);
  });
}
