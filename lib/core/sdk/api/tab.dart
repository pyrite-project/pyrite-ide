import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';

abstract class SdkTabCommands {
  static const String createFile = 'sdk.tab.create_file';
  static const String createView = 'sdk.tab.create_view';
  static const String close = 'sdk.tab.close';
  static const String list = 'sdk.tab.list';
  static const String switchTab = 'sdk.tab.switch';
}

class SdkTab {
  final Ref ref;
  SdkTab(this.ref);

  void bind(PluginRunManager runManager) {
    runManager.registerHandler(
      SdkTabCommands.createFile,
      (envelope, respond) => _handleCreateFile(runManager, envelope, respond),
    );
    runManager.registerHandler(
      SdkTabCommands.createView,
      (envelope, respond) => _handleCreateView(runManager, envelope, respond),
    );
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
    PluginRunManager runManager,
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
    runManager.sendJson(
      makeEnvelope(
        type: 'sdk.editor.open_file',
        payload: {'file_path': filePath},
        replyTo: envelope['id'],
      ),
    );
    _respondOk(envelope, respond, data: true);
  }

  /// Opens one of the calling plugin's contributed views as an editor tab.
  ///
  /// The tab hosts the same render surface as the sidebar placement, so a view
  /// gains no capability by being placed one way or the other. Responds with the
  /// allocated `instanceId`: patches and route state are per instance, so the
  /// plugin must address this one rather than reusing a sidebar instance.
  void _handleCreateView(
    PluginRunManager runManager,
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final viewId = (payload['viewId'] ?? payload['view_id'])?.toString();
    if (viewId == null || viewId.isEmpty) {
      _respondError(envelope, respond, '缺少 viewId');
      return;
    }

    final contribution = ref
        .read(contributionRegistryProvider)
        .views
        .visible
        .where(
          (entry) =>
              entry.pluginId == runManager.pluginId && entry.value.id == viewId,
        )
        .firstOrNull;
    if (contribution == null) {
      _respondError(envelope, respond, '插件未贡献视图: $viewId');
      return;
    }

    final renderer = (payload['renderer']?.toString().isNotEmpty ?? false)
        ? payload['renderer'].toString()
        : contribution.value.renderer;
    final title = payload['title']?.toString() ?? contribution.value.title;
    final expansion = payload['expansion'] == true;

    final instance = ref
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: runManager.pluginId,
          viewId: viewId,
          renderer: renderer,
          title: title,
          expansion: expansion,
        );
    if (instance == null) {
      _respondError(envelope, respond, '插件未运行，无法创建视图标签页');
      return;
    }

    _respondOk(envelope, respond, data: instance.toJson());
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
      ref
          .read(tabbedViewControllerProvider.notifier)
          .afterTabClose(index, tabs[index]);
      _respondOk(envelope, respond, data: true);
    } else if (filePath != null) {
      for (int i = 0; i < tabs.length; i++) {
        final value = tabs[i].value;
        if (value is TabDataValue && value.filePath == filePath) {
          ref
              .read(tabbedViewControllerProvider.notifier)
              .afterTabClose(i, tabs[i]);
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
      controller.onTabTap(tabs[index], index);
      _respondOk(envelope, respond, data: true);
    } else if (filePath != null) {
      for (int i = 0; i < tabs.length; i++) {
        final value = tabs[i].value;
        if (value is TabDataValue && value.filePath == filePath) {
          controller.onTabTap(tabs[i], i);
          _respondOk(envelope, respond, data: true);
          return;
        }
      }
      _respondError(envelope, respond, '未找到标签页: $filePath');
    } else {
      _respondError(envelope, respond, '需要 index 或 file_path');
    }
  }
}

final Provider<SdkTab> sdkTabProvider = Provider(SdkTab.new);
