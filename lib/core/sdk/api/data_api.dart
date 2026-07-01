import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_config.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';
import 'package:pyrite_ide/core/services/settings.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';

abstract class SdkThemeCommands {
  static const String register = 'sdk.theme.register';
  static const String get = 'sdk.theme.get';
  static const String list = 'sdk.theme.list';
}

abstract class SdkI18nCommands {
  static const String register = 'sdk.i18n.register';
  static const String get = 'sdk.i18n.get';
  static const String list = 'sdk.i18n.list';
}

abstract class SdkStubsCommands {
  static const String register = 'sdk.stubs.register';
  static const String get = 'sdk.stubs.get';
  static const String list = 'sdk.stubs.list';
  static const String resolveLayers = 'sdk.stubs.resolve_layers';
}

class SdkDataApi extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkDataApi(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkThemeCommands.register, _handleThemeRegister);
    runManager.registerHandler(SdkThemeCommands.get, _handleThemeGet);
    runManager.registerHandler(SdkThemeCommands.list, _handleThemeList);
    runManager.registerHandler(SdkI18nCommands.register, _handleI18nRegister);
    runManager.registerHandler(SdkI18nCommands.get, _handleI18nGet);
    runManager.registerHandler(SdkI18nCommands.list, _handleI18nList);
    runManager.registerHandler(
      SdkStubsCommands.register,
      (envelope, respond) => _handleStubsRegister(runManager, envelope, respond),
    );
    runManager.registerHandler(SdkStubsCommands.get, _handleStubsGet);
    runManager.registerHandler(SdkStubsCommands.list, _handleStubsList);
    runManager.registerHandler(
      SdkStubsCommands.resolveLayers,
      _handleStubsResolveLayers,
    );
  }

  void _respondOk(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond, {
    dynamic data,
  }) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.ok',
      'payload': {'data': data},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _respondError(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    String message,
  ) {
    respond({
      'version': '0.0',
      'id': '',
      'type': 'sdk.response.error',
      'payload': {'message': message},
      'reply_to': envelope['id'],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Theme handlers ──

  void _handleThemeRegister(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final name = payload['name']?.toString();
    final data = payload['data'];

    if (name == null || name.isEmpty) {
      _respondError(envelope, respond, '缺少 name');
      return;
    }

    // Store in vars (for SDK protocol compat)
    state?.vars['theme.$name'] = data;

    // Register in DataRegistry (for IDE consumption)
    if (data is Map<String, dynamic>) {
      ref.read(dataRegistryProvider).registerTheme(
            state?.pluginId ?? '',
            name,
            data,
          );
    }

    state?.onDataChanged?.call();
    _respondOk(envelope, respond, data: true);
  }

  void _handleThemeGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final name = payload['name']?.toString();

    if (name == null || name.isEmpty) {
      _respondError(envelope, respond, '缺少 name');
      return;
    }

    final data = state?.vars['theme.$name'];
    if (data == null) {
      _respondError(envelope, respond, '主题未注册: $name');
      return;
    }
    _respondOk(envelope, respond, data: {'name': name, 'data': data});
  }

  void _handleThemeList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final themes = <String>[];
    for (final key in state?.vars.keys.toList() ?? []) {
      if (key.startsWith('theme.')) {
        themes.add(key.substring(6));
      }
    }
    _respondOk(envelope, respond, data: themes);
  }

  // ── i18n handlers ──

  void _handleI18nRegister(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final locale = payload['locale']?.toString();
    final messages = payload['messages'];

    if (locale == null || locale.isEmpty) {
      _respondError(envelope, respond, '缺少 locale');
      return;
    }

    // Store in vars
    state?.vars['i18n.$locale'] = messages;

    // Register in DataRegistry
    if (messages is Map<String, dynamic>) {
      ref.read(dataRegistryProvider).registerLocale(
            state?.pluginId ?? '',
            locale,
            messages,
          );
    }

    state?.onDataChanged?.call();
    _respondOk(envelope, respond, data: true);
  }

  void _handleI18nGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final locale = payload['locale']?.toString();

    if (locale == null || locale.isEmpty) {
      _respondError(envelope, respond, '缺少 locale');
      return;
    }

    final messages = state?.vars['i18n.$locale'];
    if (messages == null) {
      _respondError(envelope, respond, '语言包未注册: $locale');
      return;
    }
    _respondOk(envelope, respond, data: {'locale': locale, 'messages': messages});
  }

  void _handleI18nList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final locales = <String>[];
    for (final key in state?.vars.keys.toList() ?? []) {
      if (key.startsWith('i18n.')) {
        locales.add(key.substring(5));
      }
    }
    _respondOk(envelope, respond, data: locales);
  }

  // ── Stubs handlers ──

  void _handleStubsRegister(
    PluginRunManager runManager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final pluginId = runManager.pluginId;
    final providerId = (payload['provider_id']?.toString().isNotEmpty == true)
        ? payload['provider_id'].toString()
        : pluginId;
    final kind = payload['kind']?.toString() ?? 'micropython';
    final version = payload['version']?.toString() ?? '';
    final rawProfiles = payload['profiles'];

    if (providerId.isEmpty) {
      _respondError(envelope, respond, '缺少 provider_id');
      return;
    }
    if (rawProfiles is! List) {
      _respondError(envelope, respond, 'profiles 必须是列表');
      return;
    }

    final profiles = <StubsProfileEntry>[];
    for (final item in rawProfiles) {
      if (item is! Map) continue;
      final profile = StubsProfileEntry.fromMap(Map<String, dynamic>.from(item));
      if (profile.id.isEmpty || profile.path.isEmpty) continue;
      profiles.add(profile);
    }
    if (profiles.isEmpty) {
      _respondError(envelope, respond, '没有有效的 stubs profile');
      return;
    }

    try {
      ref.read(dataRegistryProvider).registerStubsProvider(
            StubsProviderEntry(
              pluginId: pluginId,
              providerId: providerId,
              kind: kind,
              version: version,
              profiles: profiles,
              aliases: (payload['aliases'] as List? ?? [])
                  .map((item) => item.toString())
                  .toList(),
              metadata: Map<String, dynamic>.from(
                payload['metadata'] as Map? ?? {},
              ),
            ),
          );
      runManager.onOutput?.call(
        '[$pluginId] registered stubs provider $providerId: '
        '${profiles.map((profile) => '${profile.id}=${profile.path}').join(', ')}',
      );
      _refreshOpenLspStubsConfiguration();
    } catch (error) {
      _respondError(envelope, respond, error.toString());
      return;
    }

    runManager.onDataChanged?.call();
    _respondOk(envelope, respond, data: true);
  }

  void _refreshOpenLspStubsConfiguration() {
    final enabled = ref.read(microPythonStubsEnabled);
    final layers = ref.read(microPythonStubsLayers);
    final controllers = ref.read(editorControllerMapProvider).values.toList();
    final stubsConfig = buildLspStubsConfig(ref);
    ref.read(ideOutputLogProvider.notifier).add(
          IdeOutputSource.ide,
          'Stubs refresh requested: enabled=$enabled, '
          'layers=${layers.map((layer) => '${layer.provider}/${layer.profile}').join(', ')}, '
          'paths=${stubsConfig.paths.join(';')}, '
          'openLsp=${controllers.where((controller) => controller.lspConfig != null).length}',
        );
    if (stubsConfig.workspaceConfiguration.isEmpty) {
      ref.read(ideOutputLogProvider.notifier).add(
            IdeOutputSource.ide,
            'Skipped LSP stubs refresh: no resolved stubs paths',
          );
      return;
    }
    for (final controller in controllers) {
      final lspConfig = controller.lspConfig;
      if (lspConfig == null || !lspConfig.isInitialized) {
        continue;
      }
      ref.read(ideOutputLogProvider.notifier).add(
            IdeOutputSource.ide,
            'Refreshing LSP stubs paths: ${stubsConfig.paths.join(';')}',
          );
      unawaited(
        lspConfig.sendNotification(
          method: 'workspace/didChangeConfiguration',
          params: {'settings': stubsConfig.workspaceConfiguration},
        ),
      );
    }
  }

  void _handleStubsGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final providerId = payload['provider_id']?.toString();
    if (providerId == null || providerId.isEmpty) {
      _respondError(envelope, respond, '缺少 provider_id');
      return;
    }
    final provider = ref.read(dataRegistryProvider).getStubsProvider(providerId);
    if (provider == null) {
      _respondError(envelope, respond, '未知 stubs provider: $providerId');
      return;
    }
    _respondOk(envelope, respond, data: provider.toJson());
  }

  void _handleStubsList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final providers = ref
        .read(dataRegistryProvider)
        .allStubsProviders
        .map((entry) => entry.toJson())
        .toList();
    _respondOk(envelope, respond, data: providers);
  }

  void _handleStubsResolveLayers(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final layers = payload['layers'];
    if (layers is! List) {
      _respondError(envelope, respond, 'layers 必须是列表');
      return;
    }
    final parsedLayers = <Map<String, String>>[];
    for (final item in layers) {
      if (item is! Map) continue;
      final layer = Map<String, dynamic>.from(item);
      final providerId = layer['provider']?.toString() ??
          layer['provider_id']?.toString() ??
          '';
      final profileId = layer['profile']?.toString() ??
          layer['profile_id']?.toString() ??
          '';
      parsedLayers.add({
        'provider': providerId,
        'profile': profileId,
      });
    }
    final resolved = ref.read(dataRegistryProvider).resolveStubsLayers(parsedLayers);
    _respondOk(envelope, respond, data: resolved);
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkThemeCommands.register);
    state?.unregisterHandler(SdkThemeCommands.get);
    state?.unregisterHandler(SdkThemeCommands.list);
    state?.unregisterHandler(SdkI18nCommands.register);
    state?.unregisterHandler(SdkI18nCommands.get);
    state?.unregisterHandler(SdkI18nCommands.list);
    state?.unregisterHandler(SdkStubsCommands.register);
    state?.unregisterHandler(SdkStubsCommands.get);
    state?.unregisterHandler(SdkStubsCommands.list);
    state?.unregisterHandler(SdkStubsCommands.resolveLayers);
    super.dispose();
  }
}

final StateNotifierProvider<SdkDataApi, PluginRunManager?>
    sdkDataApiProvider = StateNotifierProvider((ref) => SdkDataApi(ref));
