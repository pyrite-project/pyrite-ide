import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/lsp_stubs_refresh.dart';
import 'package:pyrite_ide/core/services/serial/android_usb_serial_provider.dart';
import 'package:pyrite_ide/core/services/serial/desktop_usb_serial_provider.dart';
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
    _SettingEntry(name: 'editor.code_folding', type: 'bool', provider: editorCodeFolding, getter: (ref) => ref.read(editorCodeFolding), setter: (ref, v) => ref.read(editorCodeFolding.notifier).state = v == true),
    _SettingEntry(name: 'editor.guide_lines', type: 'bool', provider: editorGuideLines, getter: (ref) => ref.read(editorGuideLines), setter: (ref, v) => ref.read(editorGuideLines.notifier).state = v == true),
    _SettingEntry(name: 'editor.local_suggestions', type: 'bool', provider: editorLocalSuggestions, getter: (ref) => ref.read(editorLocalSuggestions), setter: (ref, v) => ref.read(editorLocalSuggestions.notifier).state = v == true),
    _SettingEntry(name: 'editor.keyboard_suggestions', type: 'bool', provider: editorKeyboardSuggestions, getter: (ref) => ref.read(editorKeyboardSuggestions), setter: (ref, v) => ref.read(editorKeyboardSuggestions.notifier).state = v == true),
    _SettingEntry(name: 'editor.use_space_as_tab', type: 'bool', provider: editorUseSpaceAsTab, getter: (ref) => ref.read(editorUseSpaceAsTab), setter: (ref, v) => ref.read(editorUseSpaceAsTab.notifier).state = v == true),
    _SettingEntry(name: 'editor.tab_size', type: 'int', provider: editorTabSize, getter: (ref) => ref.read(editorTabSize), setter: (ref, v) => ref.read(editorTabSize.notifier).state = (v as num).toInt()),
    _SettingEntry(name: 'editor.gutter_divider', type: 'bool', provider: editorGutterDivider, getter: (ref) => ref.read(editorGutterDivider), setter: (ref, v) => ref.read(editorGutterDivider.notifier).state = v == true),
    _SettingEntry(
      name: 'lsp.enabled',
      type: 'bool',
      provider: useLsp,
      getter: (ref) => ref.read(useLsp),
      setter: (ref, v) => ref.read(useLsp.notifier).state = v == true,
    ),
    _SettingEntry(
      name: 'lsp.type',
      type: 'string',
      provider: lspType,
      getter: (ref) => ref.read(lspType).jsonName,
      setter: (ref, v) {
        final parsed = LspType.fromJsonName(v.toString());
        if (parsed != null) ref.read(lspType.notifier).state = parsed;
      },
    ),
    _SettingEntry(
      name: 'lsp.websocket_path',
      type: 'string',
      provider: lspWebSocketPath,
      getter: (ref) => ref.read(lspWebSocketPath),
      setter: (ref, v) => ref.read(lspWebSocketPath.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'lsp.stdio_executable',
      type: 'string',
      provider: lspStdioExecutable,
      getter: (ref) => ref.read(lspStdioExecutable),
      setter: (ref, v) => ref.read(lspStdioExecutable.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'lsp.stdio_args',
      type: 'string',
      provider: lspStdioArgs,
      getter: (ref) => ref.read(lspStdioArgs),
      setter: (ref, v) => ref.read(lspStdioArgs.notifier).state = v.toString(),
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
    _SettingEntry(name: 'lsp.semantic_highlighting', type: 'bool', provider: lspSemanticHighlighting, getter: (ref) => ref.read(lspSemanticHighlighting), setter: (ref, v) => ref.read(lspSemanticHighlighting.notifier).state = v == true),
    _SettingEntry(name: 'lsp.code_completion', type: 'bool', provider: lspCodeCompletion, getter: (ref) => ref.read(lspCodeCompletion), setter: (ref, v) => ref.read(lspCodeCompletion.notifier).state = v == true),
    _SettingEntry(name: 'lsp.hover_info', type: 'bool', provider: lspHoverInfo, getter: (ref) => ref.read(lspHoverInfo), setter: (ref, v) => ref.read(lspHoverInfo.notifier).state = v == true),
    _SettingEntry(name: 'lsp.code_action', type: 'bool', provider: lspCodeAction, getter: (ref) => ref.read(lspCodeAction), setter: (ref, v) => ref.read(lspCodeAction.notifier).state = v == true),
    _SettingEntry(name: 'lsp.signature_help', type: 'bool', provider: lspSignatureHelp, getter: (ref) => ref.read(lspSignatureHelp), setter: (ref, v) => ref.read(lspSignatureHelp.notifier).state = v == true),
    _SettingEntry(name: 'lsp.document_color', type: 'bool', provider: lspDocumentColor, getter: (ref) => ref.read(lspDocumentColor), setter: (ref, v) => ref.read(lspDocumentColor.notifier).state = v == true),
    _SettingEntry(name: 'lsp.document_highlight', type: 'bool', provider: lspDocumentHighlight, getter: (ref) => ref.read(lspDocumentHighlight), setter: (ref, v) => ref.read(lspDocumentHighlight.notifier).state = v == true),
    _SettingEntry(name: 'lsp.code_folding', type: 'bool', provider: lspCodeFolding, getter: (ref) => ref.read(lspCodeFolding), setter: (ref, v) => ref.read(lspCodeFolding.notifier).state = v == true),
    _SettingEntry(name: 'lsp.inlay_hint', type: 'bool', provider: lspInlayHint, getter: (ref) => ref.read(lspInlayHint), setter: (ref, v) => ref.read(lspInlayHint.notifier).state = v == true),
    _SettingEntry(name: 'lsp.go_to_definition', type: 'bool', provider: lspGoToDefinition, getter: (ref) => ref.read(lspGoToDefinition), setter: (ref, v) => ref.read(lspGoToDefinition.notifier).state = v == true),
    _SettingEntry(name: 'lsp.rename', type: 'bool', provider: lspRename, getter: (ref) => ref.read(lspRename), setter: (ref, v) => ref.read(lspRename.notifier).state = v == true),
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
    _SettingEntry(
      name: 'webrepl.host',
      type: 'string',
      provider: webReplHost,
      getter: (ref) => ref.read(webReplHost),
      setter: (ref, v) => ref.read(webReplHost.notifier).state = v.toString(),
    ),
    _SettingEntry(
      name: 'webrepl.port',
      type: 'int',
      provider: webReplPort,
      getter: (ref) => ref.read(webReplPort),
      setter: (ref, v) => ref.read(webReplPort.notifier).state = (v as num).toInt(),
    ),
    _SettingEntry(
      name: 'webrepl.password',
      type: 'string',
      provider: webReplPassword,
      getter: (ref) => ref.read(webReplPassword),
      setter: (ref, v) => ref.read(webReplPassword.notifier).state = v.toString(),
    ),
    _SettingEntry(name: 'serial.default_baud_rate', type: 'int', provider: serialDefaultBaudRate, getter: (ref) => ref.read(serialDefaultBaudRate), setter: (ref, v) {
      final value = (v as num).toInt();
      ref.read(serialDefaultBaudRate.notifier).state = value;
      if (Platform.isAndroid) {
        ref.read(androidUsbSerialProvider.notifier).setBaudRate(value);
      } else {
        ref.read(desktopUsbSerialProvider.notifier).setBaudRate(value);
      }
    }),
    _SettingEntry(name: 'serial.auto_reconnect', type: 'bool', provider: serialAutoReconnect, getter: (ref) => ref.read(serialAutoReconnect), setter: (ref, v) {
      final value = v == true;
      ref.read(serialAutoReconnect.notifier).state = value;
      if (Platform.isAndroid) {
        ref.read(androidUsbSerialProvider.notifier).setAutoReconnect(value);
      } else {
        ref.read(desktopUsbSerialProvider.notifier).setAutoReconnect(value);
      }
    }),
    _SettingEntry(name: 'terminal.font_family', type: 'string', provider: terminalFontFamily, getter: (ref) => ref.read(terminalFontFamily), setter: (ref, v) => ref.read(terminalFontFamily.notifier).state = v.toString()),
    _SettingEntry(name: 'terminal.font_size', type: 'double', provider: terminalFontSize, getter: (ref) => ref.read(terminalFontSize), setter: (ref, v) => ref.read(terminalFontSize.notifier).state = (v as num).toDouble()),
    _SettingEntry(name: 'terminal.line_height', type: 'double', provider: terminalLineHeight, getter: (ref) => ref.read(terminalLineHeight), setter: (ref, v) => ref.read(terminalLineHeight.notifier).state = (v as num).toDouble()),
    _SettingEntry(name: 'micropython.stubs.enabled', type: 'bool', provider: microPythonStubsEnabled, getter: (ref) => ref.read(microPythonStubsEnabled), setter: (ref, v) => ref.read(microPythonStubsEnabled.notifier).state = v == true),
    _SettingEntry(name: 'micropython.stubs.auto_detect_layers', type: 'bool', provider: microPythonStubsAutoDetectLayers, getter: (ref) => ref.read(microPythonStubsAutoDetectLayers), setter: (ref, v) => ref.read(microPythonStubsAutoDetectLayers.notifier).state = v == true),
    _SettingEntry(name: 'micropython.stubs.layers', type: 'list', provider: microPythonStubsLayers, getter: (ref) => ref.read(microPythonStubsLayers).map((layer) => layer.toJson()).toList(), setter: (ref, v) {
      final list = v is List ? v : const [];
      ref.read(microPythonStubsLayers.notifier).state = list
          .whereType<Map>()
          .map((item) => MicroPythonStubsLayer.fromJson(Map<String, dynamic>.from(item)))
          .where((layer) => layer.provider.isNotEmpty && layer.profile.isNotEmpty)
          .toList();
      refreshOpenLspStubsConfiguration(ref);
    }),
    _SettingEntry(name: 'micropython.stubs.extra_paths', type: 'list', provider: microPythonStubsExtraPaths, getter: (ref) => ref.read(microPythonStubsExtraPaths), setter: (ref, v) {
      final list = v is List ? v : const [];
      ref.read(microPythonStubsExtraPaths.notifier).state = list.map((item) => item.toString()).toList();
    }),
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
