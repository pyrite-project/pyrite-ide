import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/settings.dart';

abstract class SdkSettingsCommands {
  static const String get = 'sdk.settings.get';
  static const String set = 'sdk.settings.set';
  static const String list = 'sdk.settings.list';
}

class _SettingEntry {
  final String name;
  final String type;
  final ProviderBase provider;
  final dynamic Function(Ref) getter;
  final void Function(Ref, dynamic) setter;

  const _SettingEntry({
    required this.name,
    required this.type,
    required this.provider,
    required this.getter,
    required this.setter,
  });
}

class SettingsRegistry {
  static final List<_SettingEntry> _settings = [
    _SettingEntry(
      name: 'editor.font_family',
      type: 'string',
      provider: editorTextFontProvider,
      getter: (ref) => ref.read(editorTextFontProvider),
      setter: (ref, v) => ref.read(editorTextFontProvider.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'editor.font_size',
      type: 'double',
      provider: editorFontSize,
      getter: (ref) => ref.read(editorFontSize),
      setter: (ref, v) => ref.read(editorFontSize.notifier).state = (v as num).toDouble(),
    ),
    _SettingEntry(
      name: 'editor.word_wrap',
      type: 'bool',
      provider: editorWordWrap,
      getter: (ref) => ref.read(editorWordWrap),
      setter: (ref, v) => ref.read(editorWordWrap.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'editor.line_number',
      type: 'bool',
      provider: editorLineNumber,
      getter: (ref) => ref.read(editorLineNumber),
      setter: (ref, v) => ref.read(editorLineNumber.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'lsp.enabled',
      type: 'bool',
      provider: useLsp,
      getter: (ref) => ref.read(useLsp),
      setter: (ref, v) => ref.read(useLsp.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'lsp.websocket_path',
      type: 'string',
      provider: lspWebScoketPath,
      getter: (ref) => ref.read(lspWebScoketPath),
      setter: (ref, v) => ref.read(lspWebScoketPath.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'lsp.disable_warning',
      type: 'bool',
      provider: disableWarning,
      getter: (ref) => ref.read(disableWarning),
      setter: (ref, v) => ref.read(disableWarning.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'lsp.disable_error',
      type: 'bool',
      provider: disableError,
      getter: (ref) => ref.read(disableError),
      setter: (ref, v) => ref.read(disableError.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'editor.chinese_to_unicode',
      type: 'bool',
      provider: chineseToUnicodeConversion,
      getter: (ref) => ref.read(chineseToUnicodeConversion),
      setter: (ref, v) => ref.read(chineseToUnicodeConversion.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'editor.enable_signal_detection',
      type: 'bool',
      provider: enableSignalDetection,
      getter: (ref) => ref.read(enableSignalDetection),
      setter: (ref, v) => ref.read(enableSignalDetection.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'editor.upload_confirm_style',
      type: 'string',
      provider: uploadConfirmStyleProvider,
      getter: (ref) => ref.read(uploadConfirmStyleProvider),
      setter: (ref, v) => ref.read(uploadConfirmStyleProvider.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'editor.confirm_shortcut',
      type: 'string',
      provider: confirmShortcutProvider,
      getter: (ref) => ref.read(confirmShortcutProvider),
      setter: (ref, v) => ref.read(confirmShortcutProvider.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'editor.cancel_shortcut',
      type: 'string',
      provider: cancelShortcutProvider,
      getter: (ref) => ref.read(cancelShortcutProvider),
      setter: (ref, v) => ref.read(cancelShortcutProvider.notifier).state = v.toString(),
    ),
  ];

  static final Map<String, _SettingEntry> _byName = {
    for (final e in _settings) e.name: e,
  };

  static _SettingEntry? _find(String name) => _byName[name];
  static List<Map<String, String>> listAll() =>
      _settings.map((e) => {'name': e.name, 'type': e.type}).toList();
}

class SdkSettings extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkSettings(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkSettingsCommands.get, _handleGet);
    runManager.registerHandler(SdkSettingsCommands.set, _handleSet);
    runManager.registerHandler(SdkSettingsCommands.list, _handleList);
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

  void _handleGet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final name = payload['name']?.toString();

    if (name == null || name.isEmpty) {
      _respondError(envelope, respond, '缺少 name');
      return;
    }

    final entry = SettingsRegistry._find(name);
    if (entry == null) {
      _respondError(envelope, respond, '未知设置: $name');
      return;
    }

    final value = entry.getter(ref);
    _respondOk(envelope, respond, data: {'name': name, 'value': value});
  }

  void _handleSet(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final name = payload['name']?.toString();
    final value = payload['value'];

    if (name == null || name.isEmpty) {
      _respondError(envelope, respond, '缺少 name');
      return;
    }

    final entry = SettingsRegistry._find(name);
    if (entry == null) {
      _respondError(envelope, respond, '未知设置: $name');
      return;
    }

    try {
      entry.setter(ref, value);
      _respondOk(envelope, respond, data: true);
    } catch (e) {
      _respondError(envelope, respond, '设置失败: $e');
    }
  }

  void _handleList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final settings = SettingsRegistry.listAll();
    _respondOk(envelope, respond, data: settings);
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkSettingsCommands.get);
    state?.unregisterHandler(SdkSettingsCommands.set);
    state?.unregisterHandler(SdkSettingsCommands.list);
    super.dispose();
  }
}

final StateNotifierProvider<SdkSettings, PluginRunManager?>
    sdkSettingsProvider = StateNotifierProvider((ref) => SdkSettings(ref));
