import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/message/ide_message.dart';
import 'package:pyrite_ide/core/services/plugins.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

class Plugins extends ConsumerWidget {
  const Plugins({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showPlugins = ref
        .watch(pluginManagerProvider)
        .values
        .where((p) => p.status != PluginStatus.uninstalled)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('插件'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: '注册并安装插件',
            onPressed: () => _installPlugin(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.monitor),
            tooltip: '权限监控',
            onPressed: () => context.push('/plugins/monitor'),
          ),
        ],
      ),
      body: showPlugins.isEmpty
          ? _PluginsEmptyState(onInstall: () => _installPlugin(context, ref))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: showPlugins.length,
              itemBuilder: (context, index) {
                final plugin = showPlugins[index];
                final isUsable = plugin.status == PluginStatus.usable;

                final statusText = switch (plugin.status) {
                  PluginStatus.usable => '可用',
                  PluginStatus.installing => '安装中',
                  PluginStatus.disabled => '已禁用',
                  PluginStatus.uninstalled => '已卸载',
                };

                final typeText = switch (plugin.type) {
                  PluginType.ui => 'UI',
                  PluginType.service => '服务',
                  PluginType.data => '数据',
                };

                final isUi = plugin.type == PluginType.ui;
                final isService = plugin.type == PluginType.service;
                final isRunning =
                    ref.watch(pluginRunManagerProvider)[plugin] != null;

                return ListTile(
                  title: Text(plugin.name),
                  subtitle: Text(
                    [
                      if (plugin.author.isNotEmpty) plugin.author,
                      typeText,
                      statusText,
                    ].join(' · '),
                  ),
                  onTap: isUsable && isUi
                      ? () {
                          ref.read(selectedPluginId.notifier).state = plugin.id;
                          context.push(
                            Uri(
                              path: '/plugins/body',
                              queryParameters: {'id': plugin.id},
                            ).toString(),
                          );
                        }
                      : null,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) =>
                        _handleMenuAction(context, ref, plugin, value),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 20),
                            SizedBox(width: 8),
                            Text('详细信息'),
                          ],
                        ),
                      ),
                      if (isUsable && isUi)
                        PopupMenuItem(
                          value: 'restart',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, size: 20),
                              SizedBox(width: 8),
                              Text('停止运行'),
                            ],
                          ),
                        ),
                      if (isUsable && isService && !isRunning)
                        PopupMenuItem(
                          value: 'start',
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_arrow,
                                size: 20,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text('启动', style: TextStyle(color: Colors.green)),
                            ],
                          ),
                        ),
                      if (isUsable && isService && isRunning)
                        PopupMenuItem(
                          value: 'stop',
                          child: Row(
                            children: [
                              Icon(Icons.stop, size: 20, color: Colors.orange),
                              SizedBox(width: 8),
                              Text(
                                '停止',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ],
                          ),
                        ),
                      if (isUsable)
                        PopupMenuItem(
                          value: 'disable',
                          child: Row(
                            children: [
                              Icon(Icons.pause_circle_outline, size: 20),
                              SizedBox(width: 8),
                              Text('禁用'),
                            ],
                          ),
                        ),
                      if (plugin.status == PluginStatus.disabled)
                        PopupMenuItem(
                          value: 'enable',
                          child: Row(
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                size: 20,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text('启用', style: TextStyle(color: Colors.green)),
                            ],
                          ),
                        ),
                      if (isUsable)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _installPlugin(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final zipPath = result.files.single.path!;
      showIdeSuccess(context, '正在安装插件...');
      final updatePending = await ref
          .read(pluginManagerProvider.notifier)
          .install(zipPath);
      if (updatePending && context.mounted) {
        showIdeSuccess(context, '插件更新将在重启 IDE 后生效');
      }
    } catch (e) {
      if (context.mounted) {
        showIdeError(context, '安装失败: $e');
      }
    }
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    Plugin plugin,
    String value,
  ) {
    switch (value) {
      case 'details':
        _showDetailsDialog(context, ref, plugin);
        break;
      case 'restart':
        ref.read(pluginManagerProvider.notifier).restart(plugin);
        break;
      case 'start':
        ref.read(pluginRunManagerProvider.notifier).start(plugin);
        break;
      case 'stop':
        unawaited(ref.read(pluginRunManagerProvider.notifier).stop(plugin));
        break;
      case 'disable':
        ref
            .read(pluginManagerProvider.notifier)
            .changeStatus(plugin.id, PluginStatus.disabled);
        break;
      case 'enable':
        ref
            .read(pluginManagerProvider.notifier)
            .changeStatus(plugin.id, PluginStatus.usable);
        break;
      case 'delete':
        _confirmDelete(context, ref, plugin);
        break;
    }
  }

  void _showDetailsDialog(BuildContext context, WidgetRef ref, Plugin plugin) {
    final statusText = switch (plugin.status) {
      PluginStatus.usable => '可用',
      PluginStatus.installing => '安装中',
      PluginStatus.disabled => '已禁用',
      PluginStatus.uninstalled => '已卸载',
    };

    final isRunning = ref.read(pluginRunManagerProvider)[plugin] != null;

    final typeText = switch (plugin.type) {
      PluginType.ui => 'UI',
      PluginType.service => '服务',
      PluginType.data => '数据',
    };

    const permLabels = {
      'ui': '界面',
      'file': '文件',
      'board': '开发板',
      'serial': '串口',
      'editor': '编辑器',
      'persistence': '持久化',
      'tab': '标签页',
      'settings': '设置',
      'data': '数据',
      'dialog': '对话框',
    };

    const allResourceActions = {
      'ui': ['view', 'navigate'],
      'file': ['read', 'write'],
      'board': ['read', 'write'],
      'serial': ['read', 'write'],
      'editor': ['read', 'write'],
      'persistence': ['read', 'write'],
      'tab': ['create', 'manage'],
      'settings': ['read', 'write'],
      'data': ['read', 'write'],
      'dialog': ['show'],
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget buildCategory(String resource) {
            final declared = plugin.declaredPermissions[resource];
            final isDeclared = declared != null;
            final enabled = plugin.permissions[resource];

            final masterOn =
                isDeclared &&
                enabled != null &&
                declared.every((a) => enabled.contains(a));

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    permLabels[resource] ?? resource,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  value: masterOn,
                  onChanged: isDeclared
                      ? (value) {
                          final newPerms = Map<String, List<String>>.from(
                            plugin.permissions,
                          );
                          if (value) {
                            newPerms[resource] = List.from(declared);
                          } else {
                            newPerms.remove(resource);
                          }
                          ref
                              .read(pluginManagerProvider.notifier)
                              .updatePermissions(plugin.id, newPerms);
                          setDialogState(() {});
                        }
                      : null,
                ),
                for (final action in allResourceActions[resource]!)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(action, style: const TextStyle(fontSize: 13)),
                      value: enabled?.contains(action) ?? false,
                      onChanged: isDeclared && declared.contains(action)
                          ? (value) {
                              final newPerms = Map<String, List<String>>.from(
                                plugin.permissions,
                              );
                              final current = List<String>.from(
                                newPerms[resource] ?? [],
                              );
                              if (value) {
                                if (!current.contains(action)) {
                                  current.add(action);
                                }
                              } else {
                                current.remove(action);
                              }
                              if (current.isEmpty) {
                                newPerms.remove(resource);
                              } else {
                                newPerms[resource] = current;
                              }
                              ref
                                  .read(pluginManagerProvider.notifier)
                                  .updatePermissions(plugin.id, newPerms);
                              setDialogState(() {});
                            }
                          : null,
                    ),
                  ),
              ],
            );
          }

          return AlertDialog(
            title: Text(plugin.name),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow('ID', plugin.id),
                    _detailRow('版本', plugin.version),
                    _detailRow('类型', typeText),
                    if (plugin.author.isNotEmpty)
                      _detailRow('作者', plugin.author),
                    if (plugin.description.isNotEmpty)
                      _detailRow('描述', plugin.description),
                    _detailRow('状态', statusText),
                    _detailRow('运行中', isRunning ? '是' : '否'),
                    if (plugin.platforms.isNotEmpty)
                      _detailRow('支持平台', plugin.platforms.join(', ')),
                    const SizedBox(height: 12),
                    Text(
                      '权限配置',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final resource in permLabels.keys)
                      buildCategory(resource),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Plugin plugin) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除插件「${plugin.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await ref
                    .read(pluginManagerProvider.notifier)
                    .uninstall(plugin.id);
              } catch (error) {
                if (context.mounted) {
                  showIdeError(context, '卸载失败: $error');
                }
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _PluginsEmptyState extends StatelessWidget {
  const _PluginsEmptyState({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 18),
              Text('尚未安装插件', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '从本地 ZIP 包注册插件后，它们会显示在这里。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('注册并安装插件'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PluginBody extends ConsumerStatefulWidget {
  const PluginBody({super.key, required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PluginBodyState();
}

class _PluginBodyState extends ConsumerState<PluginBody>
    with WidgetsBindingObserver {
  final Runtime _runtime = Runtime();
  final DynamicContent _data = DynamicContent();

  static const LibraryName coreName = LibraryName(<String>['core', 'widgets']);
  static const LibraryName materialName = LibraryName(<String>[
    'core',
    'material',
  ]);
  Map<String, LibraryName?> pagesLibNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPluginRunManager();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
      if (plugin == null) return;
      final runManager = ref.read(pluginRunManagerProvider)[plugin];
      if (runManager == null) return;
      runManager.sendLifecycleHook(LifecycleHook.resume.value);
      runManager.sendPageRefresh();
    }
  }

  void _loadCachedPages() {
    final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
    if (plugin == null) return;
    final runManager = ref.read(pluginRunManagerProvider)[plugin];
    if (runManager == null) return;
    if (runManager.pages.isNotEmpty) {
      _loadPages(runManager.pages);
    }
    if (runManager.vars.isNotEmpty) {
      _applyVars(runManager.vars);
    }
  }

  Future<void> _initPluginRunManager() async {
    final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
    if (plugin == null) return;

    _runtime.update(coreName, createCoreWidgets());
    _runtime.update(materialName, createPyriteMaterialWidgets());

    final runManager = ref.read(pluginRunManagerProvider)[plugin];
    if (runManager != null) {
      runManager.onRouteChanged = (currentRoute, routeStack) {
        ref.read(page.notifier).state = currentRoute;
      };
      _loadCachedPages();
      return;
    }

    await ref.read(pluginRunManagerProvider.notifier).start(plugin);

    final newRunManager = ref.read(pluginRunManagerProvider)[plugin];
    if (newRunManager != null) {
      newRunManager.onRouteChanged = (currentRoute, routeStack) {
        ref.read(page.notifier).state = currentRoute;
      };
    }
  }

  void _loadPages(Map<String, String> pages) {
    for (var entry in pages.entries) {
      try {
        final remoteWidgets = parseLibraryFile(entry.value);
        pagesLibNames.putIfAbsent(
          entry.key,
          () => LibraryName(<String>[entry.key]),
        );
        _runtime.update(pagesLibNames[entry.key]!, remoteWidgets);
      } catch (e) {
        debugPrint("Failed to parse RFW for page[${entry.key}]: $e");
      }
    }
    setState(() {});
  }

  void _applyVars(Map<String, dynamic> vars) {
    for (var entry in vars.entries) {
      _data.update(entry.key, entry.value);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pluginRunManagerProvider, (_, next) {
      final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
      if (plugin == null) return;
      final runManager = next[plugin];
      if (runManager == null) return;

      if (runManager.pages.isNotEmpty) {
        _loadPages(runManager.pages);
      }
      if (runManager.vars.isNotEmpty) {
        _applyVars(runManager.vars);
      }
    });

    final currentPage = ref.watch(page);
    if (pagesLibNames.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final libName = pagesLibNames[currentPage] ?? pagesLibNames['home'];
    if (libName == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final plugin = ref.read(pluginManagerProvider)[widget.pluginId];
    final runManager = ref.read(pluginRunManagerProvider)[plugin];
    return PopScope(
      canPop: runManager == null || runManager.routeStack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (runManager == null) return;
        runManager.popRoute();
      },
      child: RemoteWidget(
        runtime: _runtime,
        widget: FullyQualifiedWidgetName(libName, "root"),
        data: _data,
        onEvent: (String name, DynamicMap arguments) {
          debugPrint('user triggered event "$name" with data: $arguments');
          final runManager = ref.read(
            pluginRunManagerProvider,
          )[ref.read(pluginManagerProvider)[widget.pluginId]]!;
          final binding = runManager.consumeCallbackBinding(name, arguments);
          if (binding != null) {
            _data.update(binding.key, binding.value);
            setState(() {});
          }
          runManager.sendCallback(name, arguments, ref.watch(page));
        },
      ),
    );
  }
}

/*
TabBarView(
          children: [
            for (String pageLibName in pagesLibNames)
              RemoteWidget(
                runtime: _runtime,
                data: _data,
                widget: FullyQualifiedWidgetName(
                  managerNameMap[managerName]!,
                  'root',
                ),
                onEvent: (String name, DynamicMap arguments) {
                  debugPrint(
                    'user triggered event "$name" with data: $arguments',
                  );
                  sendCallback(name, arguments, managerName);
                },
              ),
          ],
        ),

final Runtime _runtime = Runtime();
  final DynamicContent _data = DynamicContent();
  late RemoteWidgetLibrary _remoteWidgets;

  static const LibraryName coreName = LibraryName(<String>['core', 'widgets']);
  static const LibraryName materialName = LibraryName(<String>[
    'core',
    'material',
  ]);
  Map<String, LibraryName?> pagesLibNames = {};
  Map<String, dynamic> pages = {};

  @override
  void initState() {
    _loadRemoteWidgets();
    super.initState();
  }

  Future<void> _loadRemoteWidgets(Plugin plugin) async {
    // Local widget library:
    _runtime.update(coreName, createCoreWidgets()); // 加载core.widgets
    _runtime.update(materialName, createPyriteMaterialWidgets()); // core.material
    _data.update('greet', <String, Object>{
      'name': 'World',
    }); // 设置一个变量 (对应sdk的data)
    pages = await ref.read(pluginRunManagerProvider)[plugin]!.getPages();
    for (var entry in pages.entries) {
      String rfwCode = entry.value;
      _remoteWidgets = parseLibraryFile(rfwCode);
      LibraryName pageLibName = LibraryName(<String>[entry.key]);
      _runtime.update(pageLibName, _remoteWidgets);
      pagesLibNames[entry.key] = pageLibName;
    }
    setState(() {});
  }
  */
