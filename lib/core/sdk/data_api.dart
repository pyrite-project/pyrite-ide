import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

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

    state?.vars['theme.$name'] = data;
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

    state?.vars['i18n.$locale'] = messages;
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

  @override
  void dispose() {
    state?.unregisterHandler(SdkThemeCommands.register);
    state?.unregisterHandler(SdkThemeCommands.get);
    state?.unregisterHandler(SdkThemeCommands.list);
    state?.unregisterHandler(SdkI18nCommands.register);
    state?.unregisterHandler(SdkI18nCommands.get);
    state?.unregisterHandler(SdkI18nCommands.list);
    super.dispose();
  }
}

final StateNotifierProvider<SdkDataApi, PluginRunManager?>
    sdkDataApiProvider = StateNotifierProvider((ref) => SdkDataApi(ref));
