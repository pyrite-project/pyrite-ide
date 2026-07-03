import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

abstract class SdkTabCommands {
  static const String createFile = 'sdk.tab.create_file';
  static const String createCustom = 'sdk.tab.create_custom';
  static const String close = 'sdk.tab.close';
  static const String list = 'sdk.tab.list';
  static const String switchTab = 'sdk.tab.switch';
}

class SdkTab extends StateNotifier<PluginRunManager?> {
  final Ref ref;
  SdkTab(this.ref) : super(null);

  void bind(PluginRunManager runManager) {
    state = runManager;
    runManager.registerHandler(SdkTabCommands.createFile, _handleCreateFile);
    runManager.registerHandler(SdkTabCommands.createCustom, _handleCreateCustom);
    runManager.registerHandler(SdkTabCommands.close, _handleClose);
    runManager.registerHandler(SdkTabCommands.list, _handleList);
    runManager.registerHandler(SdkTabCommands.switchTab, _handleSwitch);
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

  // ── Handlers ──

  void _handleCreateFile(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final filePath = payload['file_path']?.toString();

    if (filePath == null || filePath.isEmpty) {
      _respondError(envelope, respond, '缺少 file_path');
      return;
    }

    // Delegate to editor open_file — it creates a tab with the file
    state?.sendJson(makeEnvelope(
      type: 'sdk.editor.open_file',
      payload: {'file_path': filePath},
      replyTo: envelope['id'],
    ));
    _respondOk(envelope, respond, data: true);
  }

  void _handleCreateCustom(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final pageName = payload['page']?.toString();
    final pagesData = payload['pages'] as Map<String, dynamic>?;

    if (pageName == null || pageName.isEmpty) {
      _respondError(envelope, respond, '缺少 page');
      return;
    }
    if (pagesData == null || pagesData.isEmpty) {
      _respondError(envelope, respond, '缺少 pages');
      return;
    }

    // Push the RFW pages into the run manager (same as sdk.page.push)
    state?.pages.addAll(pagesData.map((k, v) => MapEntry(k, v.toString())));

    // Navigate to the custom page
    state?.currentRoute = pageName;
    state?.sendJson(makeEnvelope(
      type: 'ide.router.sync',
      payload: {
        'page': pageName,
        'stack': state?.routeStack ?? [],
      },
    ));
    state?.onDataChanged?.call();

    _respondOk(envelope, respond, data: true);
  }

  void _handleClose(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final index = payload['index'] as int?;
    final filePath = payload['file_path']?.toString();

    final tabs = ref.read(tabbedViewControllerProvider).tabs;

    if (index != null && index >= 0 && index < tabs.length) {
      ref.read(tabbedViewControllerProvider.notifier).afterTabClose(
            index,
            tabs[index],
          );
      _respondOk(envelope, respond, data: true);
    } else if (filePath != null) {
      for (int i = 0; i < tabs.length; i++) {
        final value = tabs[i].value;
        if (value is TabDataValue && value.filePath == filePath) {
          ref.read(tabbedViewControllerProvider.notifier).afterTabClose(
                i,
                tabs[i],
              );
          _respondOk(envelope, respond, data: true);
          return;
        }
      }
      _respondError(envelope, respond, '未找到标签页: $filePath');
    } else {
      _respondError(envelope, respond, '需要 index 或 file_path');
    }
  }

  void _handleList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final tabs = ref.read(tabbedViewControllerProvider).tabs;
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      if (tab.value is TabDataValue) {
        final value = tab.value as TabDataValue;
        result.add({
          'index': i,
          'path': value.filePath,
          'name': value.file?.path.split(RegExp(r'[/\\]')).last,
          'type': value.type,
        });
      }
    }
    _respondOk(envelope, respond, data: result);
  }

  void _handleSwitch(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final index = payload['index'] as int?;
    final filePath = payload['file_path']?.toString();

    final controller = ref.read(tabbedViewControllerProvider.notifier);
    final tabs = ref.read(tabbedViewControllerProvider).tabs;

    if (index != null && index >= 0 && index < tabs.length) {
      controller.state.selectedIndex = index;
      _respondOk(envelope, respond, data: true);
    } else if (filePath != null) {
      for (int i = 0; i < tabs.length; i++) {
        final value = tabs[i].value;
        if (value is TabDataValue && value.filePath == filePath) {
          controller.state.selectedIndex = i;
          _respondOk(envelope, respond, data: true);
          return;
        }
      }
      _respondError(envelope, respond, '未找到标签页: $filePath');
    } else {
      _respondError(envelope, respond, '需要 index 或 file_path');
    }
  }

  @override
  void dispose() {
    state?.unregisterHandler(SdkTabCommands.createFile);
    state?.unregisterHandler(SdkTabCommands.createCustom);
    state?.unregisterHandler(SdkTabCommands.close);
    state?.unregisterHandler(SdkTabCommands.list);
    state?.unregisterHandler(SdkTabCommands.switchTab);
    super.dispose();
  }
}

final StateNotifierProvider<SdkTab, PluginRunManager?> sdkTabProvider =
    StateNotifierProvider((ref) => SdkTab(ref));
