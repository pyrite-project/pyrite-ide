import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/expansion_page.dart';
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
    final mainTabs = ref.read(tabbedViewControllerProvider).tabs;
    for (int i = 0; i < mainTabs.length; i++) {
      final value = mainTabs[i].value;
      if (value is! TabDataValue || value.tabId != tabId) continue;
      final tab = mainTabs[i];
      ref.read(tabbedViewControllerProvider).removeTab(i);
      ref.read(tabbedViewControllerProvider.notifier).afterTabClose(i, tab);
      _respondOk(envelope, respond, data: true);
      return;
    }

    final expansionTabs = ref.read(expansionViewController).tabs;
    for (int i = 0; i < expansionTabs.length; i++) {
      final value = expansionTabs[i].value;
      if (value is! TabDataValue || value.tabId != tabId) continue;
      ref.read(expansionViewController).removeTab(i);
      ref.read(tabbedViewControllerProvider.notifier).closePluginView(value);
      final next = TabbedViewController(
        List<TabData>.from(ref.read(expansionViewController).tabs),
      );
      ref.read(expansionViewController.notifier).state = next;
      _respondOk(envelope, respond, data: true);
      return;
    }
    _respondError(envelope, respond, '未找到标签页: $tabId');
  }

  void _handleList(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
  ) {
    final result = <Map<String, dynamic>>[];
    var index = 0;
    void append(Iterable<TabData> tabs, String placement) {
      for (final tab in tabs) {
        final value = tab.value;
        if (value is! TabDataValue) continue;
        final item = <String, dynamic>{
          'index': index++,
          'tabId': value.tabId,
          'resource': value.isPluginView ? null : value.filePath,
          'name': tab.text,
          'kind': value.type,
          'placement': placement,
        };
        if (value.isPluginView) {
          item['view'] = {
            'pluginId': value.pluginId,
            'viewId': value.viewId,
            'instanceId': value.viewInstanceId,
          };
        }
        result.add(item);
      }
    }

    append(ref.read(tabbedViewControllerProvider).tabs, 'editor');
    append(ref.read(expansionViewController).tabs, 'expansion');
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
    final controller = ref.read(tabbedViewControllerProvider.notifier);
    final tabs = ref.read(tabbedViewControllerProvider).tabs;
    for (int i = 0; i < tabs.length; i++) {
      final value = tabs[i].value;
      if (value is! TabDataValue || value.tabId != tabId) continue;
      controller.onTabTap(tabs[i], i);
      _respondOk(envelope, respond, data: true);
      return;
    }

    final expansion = ref.read(expansionViewController);
    for (int i = 0; i < expansion.tabs.length; i++) {
      final value = expansion.tabs[i].value;
      if (value is! TabDataValue || value.tabId != tabId) continue;
      final next = TabbedViewController(List<TabData>.from(expansion.tabs));
      next.selectTab(expansion.tabs[i]);
      ref.read(expansionViewController.notifier).state = next;
      _respondOk(envelope, respond, data: true);
      return;
    }
    _respondError(envelope, respond, '未找到标签页: $tabId');
  }
}

final Provider<SdkTab> sdkTabProvider = Provider(SdkTab.new);
