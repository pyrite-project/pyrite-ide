import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

abstract class SdkTabCommands {
  static const String createView = 'sdk.tab.create_view';
  static const String close = 'sdk.tab.close';
  static const String list = 'sdk.tab.list';
  static const String activate = 'sdk.tab.activate';
}

class SdkTab {
  final Ref ref;
  SdkTab(this.ref);

  void bind(PluginRunManager runManager) {
    runManager.registerHandler(
      SdkTabCommands.createView,
      (envelope, respond) => _handleCreateView(runManager, envelope, respond),
    );
    runManager.registerHandler(SdkTabCommands.close, _handleClose);
    runManager.registerHandler(SdkTabCommands.list, _handleList);
    runManager.registerHandler(SdkTabCommands.activate, _handleActivate);
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
    // `expansion: true` used to open the view in the expansion panel. The
    // panel is gone; the flag is accepted and ignored, and the view opens in
    // the focused editor group like any other tab.

    final instance = ref
        .read(tabbedViewControllerProvider.notifier)
        .openPluginView(
          pluginId: runManager.pluginId,
          viewId: viewId,
          renderer: renderer,
          title: title,
        );
    if (instance == null) {
      _respondError(envelope, respond, '插件未运行，无法创建视图标签页');
      return;
    }

    final data = instance.toJson();
    data['tabId'] = TabDataValue.pluginViewPath(
      pluginId: instance.pluginId,
      viewId: instance.viewId,
      instanceId: instance.instanceId,
    );
    _respondOk(envelope, respond, data: data);
  }

  void _handleClose(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final tabId = payload['tab_id']?.toString();

    if (tabId == null || tabId.isEmpty) {
      _respondError(envelope, respond, '需要 tab_id');
      return;
    }
    final found = _findTab(tabId);
    if (found == null) {
      _respondError(envelope, respond, '未找到标签页: $tabId');
      return;
    }
    // A pinned tab -- the welcome page -- can be neither closed nor moved,
    // whatever asked for it.
    if (!found.tab.closable) {
      _respondError(envelope, respond, '该标签页不允许关闭: $tabId');
      return;
    }
    found.group.removeTab(found.group.tabs.indexOf(found.tab));
    ref.read(tabbedViewControllerProvider.notifier).afterTabClose(found.tab);
    _respondOk(envelope, respond, data: true);
  }

  /// Lists every editor tab, group by group in layout order.
  ///
  /// `group` is the index of the group holding the tab; `placement` stays
  /// `editor` for every tab now that the expansion panel is gone.
  void _handleList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final result = <Map<String, dynamic>>[];
    var index = 0;
    final groups = allEditorControllers(ref.container);
    for (var group = 0; group < groups.length; group++) {
      for (final tab in groups[group].tabs) {
        final value = tab.value;
        if (value is! TabDataValue) continue;
        result.add({
          'index': index++,
          'tabId': value.tabId,
          'resource': value.isPluginView ? null : value.filePath,
          'name': tab.text,
          'kind': value.type,
          'placement': 'editor',
          'group': group,
          if (value.isPluginView)
            'view': {
              'pluginId': value.pluginId,
              'viewId': value.viewId,
              'instanceId': value.viewInstanceId,
            },
        });
      }
    }
    _respondOk(envelope, respond, data: result);
  }

  void _handleActivate(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final payload = envelope['payload'] as Map<String, dynamic>? ?? {};
    final tabId = payload['tab_id']?.toString();

    if (tabId == null || tabId.isEmpty) {
      _respondError(envelope, respond, '需要 tab_id');
      return;
    }
    final found = _findTab(tabId);
    if (found == null) {
      _respondError(envelope, respond, '未找到标签页: $tabId');
      return;
    }
    // The group holding the tab takes focus as well, or the shared editing
    // commands would keep acting on a group the user is not looking at.
    ref.read(tabbedViewControllerProvider.notifier).focusTab(found.tab);
    _respondOk(envelope, respond, data: true);
  }

  /// The editor tab [tabId] names, and the group holding it.
  ///
  /// The editor area can be split, so every command has to look in every
  /// group -- the same ones `list` reports.
  ({TabbedViewController group, TabData tab})? _findTab(String tabId) {
    for (final group in allEditorControllers(ref.container)) {
      for (final tab in group.tabs) {
        final value = tab.value;
        if (value is TabDataValue && value.tabId == tabId) {
          return (group: group, tab: tab);
        }
      }
    }
    return null;
  }
}

final Provider<SdkTab> sdkTabProvider = Provider(SdkTab.new);
