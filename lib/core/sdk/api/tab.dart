import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/editor.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';
import 'package:pyrite_ide/core/services/editor/editor_split.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/core/services/workspace_pane.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
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

  /// Opens one of the calling plugin's contributed views.
  ///
  /// The optional `pane` payload field chooses the target:
  ///
  /// - `focused` -- the pane the user last interacted with (the default): the
  ///   console when they were last working there, otherwise the editor area;
  /// - `editor` -- the editor area's active group, the focused one, or the
  ///   primary group when none has focus;
  /// - `console` -- the docked console panel, as a tab on its strip;
  /// - a group index (a JSON number, or its decimal string) -- that editor
  ///   group, the same index `list` reports.
  ///
  /// Every placement hosts the same render surface and responds with the
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
    // panel is gone; the flag is accepted and ignored, and `pane` chooses the
    // target instead.
    final target = viewPaneFromPayload(payload['pane']);
    if (target == null) {
      _respondError(envelope, respond, '未知窗格: ${payload['pane']}');
      return;
    }

    final notifier = ref.read(tabbedViewControllerProvider.notifier);
    switch (target) {
      case FocusedPaneTarget():
        // The focused pane: the console when the user was last working there,
        // otherwise the editor area's active group -- which is where a tab
        // opens by default.
        final onConsole =
            ref.read(focusedWorkspacePaneProvider) == WorkspacePane.console;
        final instance = onConsole
            ? notifier.openPluginViewInConsole(
                pluginId: runManager.pluginId,
                viewId: viewId,
                renderer: renderer,
                title: title,
              )
            : notifier.openPluginView(
                pluginId: runManager.pluginId,
                viewId: viewId,
                renderer: renderer,
                title: title,
              );
        _respondInstance(
          envelope,
          respond,
          instance,
          placement: onConsole ? 'console' : 'editor',
        );
      case EditorPaneTarget():
        final instance = notifier.openPluginView(
          pluginId: runManager.pluginId,
          viewId: viewId,
          renderer: renderer,
          title: title,
        );
        _respondInstance(envelope, respond, instance);
      case ConsolePaneTarget():
        final instance = notifier.openPluginViewInConsole(
          pluginId: runManager.pluginId,
          viewId: viewId,
          renderer: renderer,
          title: title,
        );
        _respondInstance(envelope, respond, instance, placement: 'console');
      case GroupPaneTarget(:var index):
        final groups = allEditorControllers(ref.container);
        if (index < 0 || index >= groups.length) {
          _respondError(envelope, respond, '窗格不存在: $index');
          return;
        }
        final instance = notifier.openPluginView(
          pluginId: runManager.pluginId,
          viewId: viewId,
          renderer: renderer,
          title: title,
          targetGroup: groups[index],
        );
        _respondInstance(envelope, respond, instance);
    }
  }

  void _respondInstance(
    Map<String, dynamic> envelope,
    void Function(Map<String, dynamic>) respond,
    ViewInstanceId? instance, {
    String placement = 'editor',
  }) {
    if (instance == null) {
      _respondError(envelope, respond, '插件未运行，无法创建视图标签页');
      return;
    }
    final data = instance.toJson();
    data['placement'] = placement;
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
  /// `group` is the index of the group holding the tab; `placement` is
  /// `editor` for those, and console-hosted tabs follow with `placement`
  /// `console` and no `group` -- they live outside the editor layout tree.
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
    // Console-hosted plugin views are not documents, but the plugin opened
    // them through this API and has to be able to find and close them again.
    for (final tab in ref
        .container
        .read(consoleTabbedViewControllerProvider)
        .tabs) {
      final value = tab.value;
      if (value is! TabDataValue) continue;
      result.add({
        'index': index++,
        'tabId': value.tabId,
        'resource': null,
        'name': tab.text,
        'kind': value.type,
        'placement': 'console',
        if (value.isPluginView)
          'view': {
            'pluginId': value.pluginId,
            'viewId': value.viewId,
            'instanceId': value.viewInstanceId,
          },
      });
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
    // commands would keep acting on a group the user is not looking at. A
    // console-hosted tab brings its panel to the front instead.
    final notifier = ref.read(tabbedViewControllerProvider.notifier);
    if (!notifier.focusTab(found.tab)) notifier.focusConsoleTab(found.tab);
    _respondOk(envelope, respond, data: true);
  }

  /// The editor tab [tabId] names, and the group holding it.
  ///
  /// The editor area can be split, so every command has to look in every
  /// group -- the same ones `list` reports -- and the docked console panel
  /// holds plugin views of its own.
  ({TabbedViewController group, TabData tab})? _findTab(String tabId) {
    for (final group in allEditorControllers(ref.container)) {
      for (final tab in group.tabs) {
        final value = tab.value;
        if (value is TabDataValue && value.tabId == tabId) {
          return (group: group, tab: tab);
        }
      }
    }
    final console = ref.container.read(consoleTabbedViewControllerProvider);
    for (final tab in console.tabs) {
      final value = tab.value;
      if (value is TabDataValue && value.tabId == tabId) {
        return (group: console, tab: tab);
      }
    }
    return null;
  }
}

final Provider<SdkTab> sdkTabProvider = Provider(SdkTab.new);
