import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/utils.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

class Plugins extends ConsumerWidget {
  const Plugins({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<Plugin> showPlugins = [];
    for (final p in ref.watch(pluginManagerProvider).entries) {
      if (p.value.permissions.contains(PluginPermission.ui)) {
        showPlugins.add(p.value);
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text('插件')),
      body: Column(
        children: [
          FilledButton(
            onPressed: () async {
              await install(
                Plugin(
                  id: "test",
                  name: "test",
                  permissions: [PluginPermission.ui],
                ),
                "E:\\Can1425\\pyrite_ide\\python.zip",
              );
              ref
                  .read(pluginManagerProvider.notifier)
                  .register(
                    Plugin(
                      id: "test",
                      name: "test",
                      permissions: [PluginPermission.ui],
                    ),
                  );
            },
            child: Text("注册并安装"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: showPlugins.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(showPlugins[index].name),
                  subtitle: Text(showPlugins[index].status.toString()),
                  onTap: () => context.go(
                    Uri(
                      path: '/plugins/body',
                      queryParameters: {'id': showPlugins[index].id},
                    ).toString(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final StateProvider<String> page = StateProvider((ref) => "home");

class PluginBody extends ConsumerStatefulWidget {
  const PluginBody({super.key, required this.pluginId});

  final String pluginId;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PluginBodyState();
}

class _PluginBodyState extends ConsumerState<PluginBody> {
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

  Future<void> _loadRemoteWidgets() async {
    // Local widget library:
    _runtime.update(coreName, createCoreWidgets());
    _runtime.update(materialName, createMaterialWidgets());
    ref
        .read(pluginRunManagerProvider.notifier)
        .start(ref.read(pluginManagerProvider)[widget.pluginId]!);
    pages = await ref
        .read(pluginRunManagerProvider)[ref.read(
          pluginManagerProvider,
        )[widget.pluginId]]!
        .getPages();
    for (var entry in pages.entries) {
      String rfwCode = entry.value;
      _remoteWidgets = parseLibraryFile(rfwCode);
      LibraryName pageLibName = LibraryName(<String>[entry.key]);
      _runtime.update(pageLibName, _remoteWidgets);
      pagesLibNames[entry.key] = pageLibName;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RemoteWidget(
        runtime: _runtime,
        widget: FullyQualifiedWidgetName(
          pagesLibNames[ref.watch(page)]!,
          "root",
          // widget,
        ),
        data: _data,
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
    _runtime.update(materialName, createMaterialWidgets()); // core.material
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
