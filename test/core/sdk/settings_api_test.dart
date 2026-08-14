import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/api/persistence.dart';
import 'package:pyrite_ide/core/sdk/api/settings_api.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/sdk/plugin_transport.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/settings.dart';

class _SettingsTransport implements PluginTransport {
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  final StreamController<PluginTransportState> _states =
      StreamController<PluginTransportState>.broadcast();
  FutureOr<void> Function(Uint8List message)? onSend;
  bool _closed = false;

  @override
  String get type => 'Fake';

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<PluginTransportState> get states => _states.stream;

  @override
  Future<void> start() async {
    if (_closed) throw StateError('Settings transport is closed');
    _states.add(PluginTransportState.connecting);
    _states.add(PluginTransportState.ready);
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_closed) throw StateError('Settings transport is closed');
    await onSend?.call(message);
  }

  void emit(Map<String, dynamic> envelope) {
    _messages.add(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _states.add(PluginTransportState.closing);
    _states.add(PluginTransportState.closed);
    await _messages.close();
    await _states.close();
  }
}

class _SettingsHarness {
  _SettingsHarness._(this.container, this._ownsContainer);

  final ProviderContainer container;
  final bool _ownsContainer;
  final StreamController<Map<String, dynamic>> _responses =
      StreamController<Map<String, dynamic>>.broadcast();

  late final PluginRunManager manager;
  late final _SettingsTransport transport;
  int _sdkSequence = 2;

  static Future<_SettingsHarness> start({
    Map<String, List<String>> permissions = const {
      'settings': ['read', 'write'],
    },
    String pluginId = 'settings-test',
    String assetsPath = '.',
    ProviderContainer? container,
  }) async {
    final harness = _SettingsHarness._(
      container ?? ProviderContainer(),
      container == null,
    );
    harness.transport = _SettingsTransport();
    harness.transport.onSend = (message) {
      final envelope = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
      switch (envelope['type']) {
        case IdeCommands.initialize:
          harness.transport.emit(
            makeEnvelope(
              type: SdkCommands.initialize,
              pluginId: envelope['pluginId'] as String,
              sessionId: envelope['sessionId'] as String,
              generation: envelope['generation'] as int,
              replyTo: envelope['requestId'] as String,
              sequence: 1,
              payload: {
                'protocolVersion': 1,
                'sdkVersion': 'fixture',
                'capabilities': ['sdk.v1'],
              },
            ),
          );
        case IdeCommands.initialized:
          harness.transport.emit(
            makeEnvelope(
              type: SdkCommands.ready,
              pluginId: envelope['pluginId'] as String,
              sessionId: envelope['sessionId'] as String,
              generation: envelope['generation'] as int,
              replyTo: envelope['requestId'] as String,
              sequence: 2,
              payload: {
                'capabilities': ['sdk.v1'],
              },
            ),
          );
        default:
          harness._responses.add(envelope);
      }
    };

    harness.manager = PluginRunManager(
      transport: harness.transport,
      assetsPath: assetsPath,
      pluginId: pluginId,
      pluginPermissions: permissions,
    );
    harness.container.read(sdkSettingsProvider).bind(harness.manager);
    harness.container.read(sdkPersistenceProvider).bind(harness.manager);

    await harness.manager.connect();
    return harness;
  }

  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final envelope = makeEnvelope(
      type: type,
      payload: payload,
      pluginId: manager.pluginId,
      sessionId: manager.sessionId,
      generation: manager.generation,
      sequence: ++_sdkSequence,
    );
    final response = _responses.stream
        .firstWhere((item) => item['replyTo'] == envelope['requestId'])
        .timeout(const Duration(seconds: 5));
    transport.emit(envelope);
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
    await _responses.close();
    if (_ownsContainer) container.dispose();
  }
}

void _expectOk(Map<String, dynamic> response, dynamic data) {
  expect(response['type'], SdkCommands.responseOk);
  expect(response['payload'], {'data': data});
  expect(response['replyTo'], isNotEmpty);
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

  test('theme settings set, get, and list over transport', () async {
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

  test('terminal background override can be set, read, and listed', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);

    final listResponse = await harness.list();
    final settings = listResponse['payload']['data'] as List<dynamic>;
    expect(
      settings.whereType<Map>().any(
        (item) =>
            item['name'] == 'terminal.override_background' &&
            item['type'] == 'bool',
      ),
      isTrue,
    );

    _expectOk(await harness.set('terminal.override_background', true), true);
    expect(harness.container.read(terminalOverrideBackground), isTrue);
    _expectOk(await harness.get('terminal.override_background'), {
      'name': 'terminal.override_background',
      'value': true,
    });
  });

  test('inlay hint display setting can be set, read, and listed', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);

    final listResponse = await harness.list();
    final settings = listResponse['payload']['data'] as List<dynamic>;
    expect(
      settings.whereType<Map>().any(
        (item) =>
            item['name'] == 'lsp.show_inlay_hints' && item['type'] == 'bool',
      ),
      isTrue,
    );
    expect(
      settings.whereType<Map>().any((item) => item['name'] == 'lsp.inlay_hint'),
      isFalse,
    );

    _expectOk(await harness.set('lsp.show_inlay_hints', true), true);
    expect(harness.container.read(lspShowInlayHints), isTrue);
    _expectOk(await harness.get('lsp.show_inlay_hints'), {
      'name': 'lsp.show_inlay_hints',
      'value': true,
    });
  });

  test('virtual environment setting can be set, read, and listed', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);

    final listResponse = await harness.list();
    final settings = listResponse['payload']['data'] as List<dynamic>;
    expect(
      settings.whereType<Map>().any(
        (item) =>
            item['name'] == 'lsp.virtual_environment' &&
            item['type'] == 'string',
      ),
      isTrue,
    );
    expect(
      settings.whereType<Map>().any(
        (item) => item['name'] == 'lsp.python_interpreter',
      ),
      isFalse,
    );

    _expectOk(
      await harness.set('lsp.virtual_environment', '/workspace/.venv'),
      true,
    );
    expect(harness.container.read(lspVirtualEnvironment), '/workspace/.venv');
    _expectOk(await harness.get('lsp.virtual_environment'), {
      'name': 'lsp.virtual_environment',
      'value': '/workspace/.venv',
    });
  });

  test(
    'BasedPyright type checking mode can be set, read, and listed',
    () async {
      final harness = await _SettingsHarness.start();
      addTearDown(harness.close);

      final listResponse = await harness.list();
      final settings = listResponse['payload']['data'] as List<dynamic>;
      expect(
        settings.whereType<Map>().any(
          (item) =>
              item['name'] == 'lsp.basedpyright.type_checking_mode' &&
              item['type'] == 'string',
        ),
        isTrue,
      );

      _expectOk(
        await harness.set('lsp.basedpyright.type_checking_mode', 'strict'),
        true,
      );
      expect(
        harness.container.read(lspBasedPyrightTypeCheckingMode),
        BasedPyrightTypeCheckingMode.strict,
      );
      _expectOk(await harness.get('lsp.basedpyright.type_checking_mode'), {
        'name': 'lsp.basedpyright.type_checking_mode',
        'value': 'strict',
      });
    },
  );

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

  test('read-only settings permission denies set over transport', () async {
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
    expect(denied['type'], SdkCommands.responseError);
    expect(denied['payload']['code'], 'permission_denied');
    expect(denied['payload']['message'], 'Permission denied: settings:write');
    expect(denied['payload']['details'], {'required': 'settings:write'});
    expect(harness.container.read(themeMode), ThemeMode.system);
  });

  test('empty and unrelated permissions fail closed', () async {
    for (final permissions in <Map<String, List<String>>>[
      const {},
      const {
        'editor': ['read'],
      },
    ]) {
      final harness = await _SettingsHarness.start(permissions: permissions);
      try {
        final denied = await harness.get('theme.mode');
        expect(denied['type'], SdkCommands.responseError);
        expect(denied['payload']['code'], 'permission_denied');
        expect(denied['payload']['details'], {'required': 'settings:read'});
      } finally {
        await harness.close();
      }
    }
  });

  test('unknown SDK command returns a stable error', () async {
    final harness = await _SettingsHarness.start();
    addTearDown(harness.close);

    final response = await harness.request('sdk.fixture.missing');

    expect(response['type'], SdkCommands.responseError);
    expect(response['payload']['code'], 'unknown_command');
    expect(response['payload']['message'], contains('sdk.fixture.missing'));
  });

  test(
    'two plugins keep independent persistence contexts when interleaved',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pyrite-context-test-',
      );
      final secondData = Directory('${root.path}/second/data/shared');
      await secondData.create(recursive: true);
      await File(
        '${secondData.path}/value.json',
      ).writeAsString(jsonEncode('second'));
      final container = ProviderContainer();
      final first = await _SettingsHarness.start(
        pluginId: 'context-first',
        assetsPath: '${root.path}/first',
        permissions: const {
          'persistence': ['read', 'write'],
        },
        container: container,
      );
      final second = await _SettingsHarness.start(
        pluginId: 'context-second',
        assetsPath: '${root.path}/second',
        permissions: const {
          'persistence': ['read'],
        },
        container: container,
      );
      addTearDown(() async {
        await first.close();
        await second.close();
        container.dispose();
        await root.delete(recursive: true);
      });

      final writes = await Future.wait([
        first.request(
          SdkPersistenceCommands.set,
          payload: {'group': 'shared', 'key': 'value', 'value': 'first'},
        ),
        second.request(
          SdkPersistenceCommands.set,
          payload: {'group': 'shared', 'key': 'value', 'value': 'second'},
        ),
      ]);
      expect(writes[0]['type'], SdkCommands.responseOk);
      expect(writes[1]['type'], SdkCommands.responseError);
      expect(writes[1]['payload']['code'], 'permission_denied');
      expect(writes[1]['payload']['details'], {
        'required': 'persistence:write',
      });

      final reads = await Future.wait([
        second.request(
          SdkPersistenceCommands.get,
          payload: {'group': 'shared', 'key': 'value'},
        ),
        first.request(
          SdkPersistenceCommands.get,
          payload: {'group': 'shared', 'key': 'value'},
        ),
      ]);

      expect(reads[0]['payload'], {'data': 'second'});
      expect(reads[1]['payload'], {'data': 'first'});
      expect(first.manager.sessionId, isNot(second.manager.sessionId));
    },
  );
}
