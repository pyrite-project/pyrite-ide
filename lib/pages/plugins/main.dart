import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager_provider.dart';
import 'package:pyrite_ide/core/sdk/types.dart';
import 'package:pyrite_ide/core/services/plugins.dart';
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
              await ref
                  .read(pluginManagerProvider.notifier)
                  .install(
                    Plugin(
                      id: "old",
                      name: "old",
                      permissions: [PluginPermission.ui],
                    ),
                    (await openFile())!.path,
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
                  onTap: () {
                    ref.read(selectedPluginId.notifier).state =
                        showPlugins[index].id;
                    context.push(
                      Uri(
                        path: '/plugins/body',
                        queryParameters: {'id': showPlugins[index].id},
                      ).toString(),
                    );
                  },
                );
              },
            ),
          ),
        ],
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

class _PluginBodyState extends ConsumerState<PluginBody> {
  final Runtime _runtime = Runtime();
  final DynamicContent _data = DynamicContent();

  static const LibraryName coreName = LibraryName(<String>['core', 'widgets']);
  static const LibraryName materialName = LibraryName(<String>['core', 'material',]);
  Map<String, LibraryName?> pagesLibNames = {};

  Map<String, String>? _lastPages;
  Map<String, dynamic>? _lastVars;

  @override
  void initState() {
    super.initState();
    _initPluginRunManager();
  }

  Future<void> _initPluginRunManager() async {
    await ref
        .read(pluginRunManagerProvider.notifier)
        .start(ref.read(pluginManagerProvider)[widget.pluginId]!);
    _runtime.update(coreName, createCoreWidgets());
    _runtime.update(materialName, createMaterialWidgets());
  }

  void _loadPages(Map<String, String> pages) {
    for (var entry in pages.entries) {
      String rfwCode = entry.value;
      try {
        RemoteWidgetLibrary remoteWidgets = parseLibraryFile(rfwCode);
        if (!pagesLibNames.containsKey(entry.key)) {
          LibraryName pageLibName = LibraryName(<String>[entry.key]);
          pagesLibNames[entry.key] = pageLibName;
        }
        _runtime.update(pagesLibNames[entry.key]!, remoteWidgets);
      } catch (e) {
        print("Failed to parse RFW for page[${entry.key}]: $e");
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

      final pages = next[plugin]?.pages;
      if (pages != null && pages.isNotEmpty && pages != _lastPages) {
        _lastPages = pages;
        _loadPages(pages);
      }

      final vars = next[plugin]?.vars;
      if (vars != null && vars != _lastVars) {
        _lastVars = vars;
        _applyVars(vars);
      }
    });

    if (pagesLibNames.isEmpty) {
      return Text("");
    }
    return Scaffold(
      body: RemoteWidget(
        runtime: _runtime,
        widget: FullyQualifiedWidgetName(
          pagesLibNames[ref.watch(page)]!,
          "root",
          // widget,
        ),
        data: _data,
        onEvent: (String name, DynamicMap arguments) {
          debugPrint('user triggered event "$name" with data: $arguments');
          ref
              .read(pluginRunManagerProvider)[ref.read(
                pluginManagerProvider,
              )[widget.pluginId]]!
              .sendCallback(name, arguments, ref.watch(page));
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
