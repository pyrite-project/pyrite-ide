import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/plugin_view/component_builder.dart';
import 'package:pyrite_ide/features/plugin_view/component_error_boundary.dart';
import 'package:pyrite_ide/features/plugin_view/component_host_state.dart';
import 'package:pyrite_ide/features/plugin_view/native_view_registry.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_markdown.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_split_view.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_video_player.dart';

/// One recorded component event.
typedef _Event = ({String id, String event, Map<String, dynamic> payload});

class _Harness {
  _Harness({Duration debounce = const Duration(milliseconds: 200)})
    : hostState = ComponentHostState(
        instance: const ViewInstanceId(
          pluginId: 'test.plugin',
          sessionId: 'test-session',
          viewId: 'test.view',
          instanceId: 'test-instance',
        ),
        debounce: debounce,
      );

  final ComponentHostState hostState;
  final List<_Event> events = [];

  late final ComponentBuilder builder = ComponentBuilder(
    registry: ComponentRegistry(),
    hostState: hostState,
    onEvent: (id, event, payload) =>
        events.add((id: id, event: event, payload: payload)),
  );

  void dispose() => hostState.dispose();
}

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? ThemeData(colorSchemeSeed: Colors.blue),
  home: Scaffold(body: child),
);

void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  group('error boundary', () {
    testWidgets('an unknown component renders a diagnosable panel, not a '
        'crash', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                harness.builder.build(context, {'type': 'Frobnicator'}),
          ),
        ),
      );
      expect(find.byType(ComponentErrorBoundary), findsOneWidget);
      expect(find.textContaining('unknown component'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a mistyped property is reported with its path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Text',
              'props': {'value': 123},
            }),
          ),
        ),
      );
      expect(find.textContaining('root.props.value'), findsOneWidget);
      expect(find.textContaining('expected string'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a deep tree beyond the limit does not crash', (tester) async {
      Map<String, dynamic> nest(int depth) => depth == 0
          ? {
              'type': 'Text',
              'props': {'value': 'leaf'},
            }
          : {
              'type': 'Column',
              'children': [nest(depth - 1)],
            };
      final builder = ComponentBuilder(
        registry: ComponentRegistry(),
        hostState: harness.hostState,
        onEvent: (_, _, _) {},
        limits: const ComponentLimits(maxDepth: 3),
      );
      await tester.pumpWidget(
        _wrap(Builder(builder: (context) => builder.build(context, nest(8)))),
      );
      expect(find.byType(ComponentErrorBoundary), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('component events', () {
    testWidgets('pressing a Button emits press', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Button',
              'props': {'id': 'save', 'label': 'Save'},
            }),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      expect(harness.events.single.id, 'save');
      expect(harness.events.single.event, 'press');
    });

    testWidgets('a disabled Button emits nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Button',
              'props': {'id': 'save', 'label': 'Save', 'enabled': false},
            }),
          ),
        ),
      );
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(harness.events, isEmpty);
    });

    testWidgets('toggling a Checkbox emits change immediately', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Checkbox',
              'props': {'id': 'flag', 'value': false, 'label': 'Enable'},
            }),
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox));
      expect(harness.events.single.event, 'change');
      expect(harness.events.single.payload['value'], true);
    });

    testWidgets('selecting a VirtualList row emits select with the item id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 200,
            child: Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'VirtualList',
                'props': {
                  'id': 'list',
                  'items': [
                    {'id': 'a', 'label': 'Alpha'},
                    {'id': 'b', 'label': 'Beta'},
                  ],
                },
              }),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Beta'));
      expect(harness.events.single.event, 'select');
      expect(harness.events.single.payload['itemId'], 'b');
    });

    testWidgets('expanding a TreeView node emits expand', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 200,
            child: Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'TreeView',
                'props': {
                  'id': 'tree',
                  'nodes': [
                    {'id': 'r', 'label': 'Root', 'hasChildren': true},
                  ],
                  'expandedIds': <String>[],
                },
              }),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(harness.events.single.event, 'expand');
      expect(harness.events.single.payload['nodeId'], 'r');
    });

    testWidgets('PropertyGrid renders typed rows and requests lazy children', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 200,
            width: 360,
            child: Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'PropertyGrid',
                'props': {
                  'id': 'variables',
                  'entries': [
                    {
                      'id': 'items',
                      'name': 'items',
                      'type': 'list',
                      'repr': '[1, 2]',
                      'icon': 'material:data_array',
                      'iconColor': 'primary',
                      'hasChildren': true,
                      'childrenState': 'unloaded',
                    },
                  ],
                },
              }),
            ),
          ),
        ),
      );

      expect(find.text('items'), findsOneWidget);
      expect(find.text('list'), findsOneWidget);
      expect(find.text('[1, 2]'), findsOneWidget);
      expect(find.byIcon(Icons.data_array), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(harness.events.map((event) => event.event), ['requestChildren']);
      expect(harness.events.last.payload['nodeId'], 'items');
    });
  });

  group('input state stays host-local', () {
    testWidgets('typing renders immediately and debounces the change event', (
      tester,
    ) async {
      final local = _Harness(debounce: const Duration(milliseconds: 100));
      addTearDown(local.dispose);
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => local.builder.build(context, {
              'type': 'TextField',
              'props': {'id': 'query', 'value': ''},
            }),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      // Text is on screen before any event crosses to the plugin.
      expect(find.text('ab'), findsOneWidget);
      expect(local.events, isEmpty);

      await tester.pump(const Duration(milliseconds: 150));
      expect(local.events.single.event, 'change');
      expect(local.events.single.payload['value'], 'ab');
    });

    testWidgets('rapid typing collapses into a single change event', (
      tester,
    ) async {
      final local = _Harness(debounce: const Duration(milliseconds: 100));
      addTearDown(local.dispose);
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => local.builder.build(context, {
              'type': 'TextField',
              'props': {'id': 'query', 'value': ''},
            }),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 150));

      expect(local.events, hasLength(1));
      expect(local.events.single.payload['value'], 'abc');
    });

    testWidgets('a late plugin value does not clobber an active edit', (
      tester,
    ) async {
      // The host state is what survives rebuilds, so simulate the plugin
      // re-sending a stale value while the field is focused.
      Widget field(String pluginValue) => _wrap(
        Builder(
          builder: (context) => harness.builder.build(context, {
            'type': 'TextField',
            'props': {'id': 'query', 'value': pluginValue},
          }),
        ),
      );

      await tester.pumpWidget(field(''));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'user typing');
      await tester.pump();

      // Plugin echoes an older value; the local buffer must win.
      await tester.pumpWidget(field('stale'));
      await tester.pump();
      expect(find.text('user typing'), findsOneWidget);
      expect(find.text('stale'), findsNothing);

      // Let the debounce fire so no timer outlives the test.
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('focus survives a rebuild', (tester) async {
      Widget field(String label) => _wrap(
        Builder(
          builder: (context) => harness.builder.build(context, {
            'type': 'TextField',
            'props': {'id': 'query', 'value': '', 'label': label},
          }),
        ),
      );
      await tester.pumpWidget(field('Search'));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(harness.hostState.hasFocus('query'), isTrue);

      // A new snapshot from the plugin rebuilds the tree.
      await tester.pumpWidget(field('Search files'));
      await tester.pump();
      expect(harness.hostState.hasFocus('query'), isTrue);
    });

    testWidgets('submitting flushes without waiting for the debounce', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'TextField',
              'props': {'id': 'query', 'value': ''},
            }),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'go');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(harness.events.any((e) => e.event == 'submit'), isTrue);
    });
  });

  group('base component controller', () {
    testWidgets(
      'mounted bounds and focus operate on any component with an id',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'Text',
                'props': {'id': 'heading', 'value': 'Heading'},
              }),
            ),
          ),
        );

        expect(
          await harness.hostState.invokeComponentMethod(
            'heading',
            'is_mounted',
            const {},
          ),
          isTrue,
        );
        final bounds =
            await harness.hostState.invokeComponentMethod(
                  'heading',
                  'get_bounds',
                  const {},
                )
                as Map<String, dynamic>;
        expect(bounds['width'], greaterThan(0));
        expect(bounds['height'], greaterThan(0));

        await harness.hostState.invokeComponentMethod(
          'heading',
          'request_focus',
          const {},
        );
        await tester.pump();
        expect(harness.hostState.hasFocus('heading'), isTrue);
        await harness.hostState.invokeComponentMethod(
          'heading',
          'unfocus',
          const {},
        );
        await tester.pump();
        expect(harness.hostState.hasFocus('heading'), isFalse);
      },
    );
  });

  group('completed native components', () {
    testWidgets('Image and Video resolve plugin-scoped resources', (
      tester,
    ) async {
      final tempParent = Directory(
        path.join(Directory.current.path, 'build', 'test_temp'),
      )..createSync(recursive: true);
      final root = tempParent.createTempSync('pyrite-media-');
      addTearDown(() => root.deleteSync(recursive: true));
      final assets = Directory(path.join(root.path, 'assets'))..createSync();
      File(
        path.join(assets.path, 'image.png'),
      ).writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
      File(
        path.join(assets.path, 'video.mp4'),
      ).writeAsBytesSync([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70]);
      final builder = ComponentBuilder(
        registry: ComponentRegistry(),
        hostState: harness.hostState,
        onEvent: (_, _, _) {},
        pluginRootPath: root.path,
      );
      late Widget imageWidget;
      late Widget videoWidget;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              imageWidget = builder.build(context, {
                'type': 'Image',
                'props': {'src': 'plugin-resource:///assets/image.png'},
              });
              videoWidget = builder.build(context, {
                'type': 'Video',
                'props': {'src': 'plugin-resource:///assets/video.mp4'},
              });
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(imageWidget, isA<Image>());
      expect((imageWidget as Image).image, isA<FileImage>());
      expect(videoWidget, isA<PluginVideoPlayer>());
      expect(
        (videoWidget as PluginVideoPlayer).source,
        path.join(root.path, 'assets', 'video.mp4'),
      );
    });

    testWidgets('Markdown uses markdown_widget and emits typed link payload', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Markdown',
              'props': {
                'id': 'docs',
                'value': '# Title\n\n[Pyrite](https://example.com)',
              },
              'events': {'linkTap': true},
            }),
          ),
        ),
      );

      final markdown = tester.widget<PluginMarkdown>(
        find.byType(PluginMarkdown),
      );
      markdown.onTapLink!('https://example.com');
      expect(find.text('Title'), findsOneWidget);
      expect(harness.events.single.event, 'linkTap');
      expect(harness.events.single.payload['href'], 'https://example.com');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('SplitView divider changes the pane ratio', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 200,
            child: Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'SplitView',
                'props': {'direction': 'horizontal', 'initialRatio': 0.5},
                'children': [
                  {
                    'type': 'Text',
                    'props': {'value': 'Left'},
                  },
                  {
                    'type': 'Text',
                    'props': {'value': 'Right'},
                  },
                ],
              }),
            ),
          ),
        ),
      );

      final before = tester.widget<Expanded>(find.byType(Expanded).first).flex;
      await tester.drag(
        find.byKey(const ValueKey('plugin-split-divider-0')),
        const Offset(80, 0),
      );
      await tester.pump();
      final after = tester.widget<Expanded>(find.byType(Expanded).first).flex;
      expect(find.byType(PluginSplitView), findsOneWidget);
      expect(after, greaterThan(before));
    });

    testWidgets('Dialog opens in the host navigator and reports dismissal', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Dialog',
              'props': {'id': 'confirm', 'title': 'Confirm', 'open': true},
              'events': {'close': true},
              'children': [
                {
                  'type': 'Text',
                  'props': {'value': 'Continue?'},
                },
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Continue?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.events.single.event, 'close');
      expect(harness.events.single.id, 'confirm');
    });

    testWidgets(
      'Dialog controller opens and closes the real route with a result',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => harness.builder.build(context, {
                'type': 'Dialog',
                'props': {
                  'id': 'controlled',
                  'title': 'Controlled',
                  'open': false,
                },
                'children': [
                  {
                    'type': 'Text',
                    'props': {'value': 'Body'},
                  },
                ],
              }),
            ),
          ),
        );

        expect(
          await harness.hostState.invokeComponentMethod(
            'controlled',
            'show',
            const {},
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        expect(
          await harness.hostState.invokeComponentMethod(
            'controlled',
            'close',
            const {'result': 'done'},
          ),
          'done',
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(harness.events, isEmpty);
      },
    );
  });

  group('theme', () {
    testWidgets('components follow the host theme, including dark mode', (
      tester,
    ) async {
      Widget page(ThemeData theme) => _wrap(
        Builder(
          builder: (context) => harness.builder.build(context, {
            'type': 'Text',
            'props': {'value': 'themed', 'style': 'title'},
          }),
        ),
        theme: theme,
      );

      // Render the same muted Text under both themes in one tree, so the
      // comparison can't be confused by rebuild timing.
      Widget muted(String label, ThemeData theme) => Theme(
        data: theme,
        child: Builder(
          builder: (context) => harness.builder.build(context, {
            'type': 'Text',
            'props': {'value': label, 'muted': true},
          }),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              muted('light-text', ThemeData.light()),
              muted('dark-text', ThemeData.dark()),
            ],
          ),
        ),
      );

      final lightColor = tester
          .widget<Text>(find.text('light-text'))
          .style
          ?.color;
      final darkColor = tester
          .widget<Text>(find.text('dark-text'))
          .style
          ?.color;

      // Muted text resolves onSurfaceVariant from whichever scheme is in scope.
      expect(lightColor, ThemeData.light().colorScheme.onSurfaceVariant);
      expect(darkColor, ThemeData.dark().colorScheme.onSurfaceVariant);
      expect(darkColor, isNot(lightColor));

      // A styled (non-muted) Text still picks up the host text theme.
      await tester.pumpWidget(page(ThemeData.light()));
      expect(tester.widget<Text>(find.text('themed')).style, isNotNull);
    });
  });

  group('acceptance: a full page from Toolbar + SearchField + VirtualList', () {
    testWidgets('composes and stays interactive', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => harness.builder.build(context, {
              'type': 'Column',
              'props': {'gap': 4},
              'children': [
                {
                  'type': 'Toolbar',
                  'props': {'dense': true},
                  'children': [
                    {
                      'type': 'IconButton',
                      'props': {'id': 'refresh', 'icon': 'material:refresh'},
                    },
                    {
                      'type': 'Badge',
                      'props': {'label': '2 results', 'tone': 'info'},
                    },
                  ],
                },
                {
                  'type': 'TextField',
                  'props': {'id': 'search', 'placeholder': 'Search symbols'},
                },
                {
                  'type': 'Flex',
                  'props': {'direction': 'vertical'},
                  'children': [
                    {
                      'type': 'VirtualList',
                      'props': {
                        'id': 'results',
                        'items': [
                          {
                            'id': 'w',
                            'label': 'Widget',
                            'icon': 'material:code',
                          },
                          {
                            'id': 'b',
                            'label': 'build',
                            'icon': 'material:code',
                          },
                        ],
                        'selectedId': 'w',
                      },
                    },
                  ],
                },
              ],
            }),
          ),
        ),
      );

      // Everything rendered, no error boundary anywhere.
      expect(find.byType(ComponentErrorBoundary), findsNothing);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('2 results'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Widget'), findsOneWidget);
      expect(find.text('build'), findsOneWidget);

      // The toolbar button and the list are both live.
      await tester.tap(find.byIcon(Icons.refresh));
      expect(harness.events.single.id, 'refresh');
      harness.events.clear();

      await tester.tap(find.text('build'));
      expect(harness.events.single.payload['itemId'], 'b');
      expect(tester.takeException(), isNull);
    });
  });

  group('native view registry', () {
    NativeViewContext viewFor(
      List<Map<String, dynamic>> nodes, {
      ViewState state = ViewState.ready,
      Map<String, dynamic> props = const {},
    }) => NativeViewContext(
      instance: const ViewInstanceId(
        pluginId: 'p',
        sessionId: 's',
        viewId: 'outline',
        instanceId: 'i',
      ),
      nodes: nodes,
      state: state,
      builder: harness.builder,
      onEvent: harness.builder.onEvent,
      props: props,
    );

    testWidgets('every renderer token builds without an error boundary', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      for (final token in RendererTokens.all) {
        final nodes = switch (token) {
          RendererTokens.variableInspector => [
            {'id': 'v1', 'name': 'items', 'value': '[1, 2]'},
          ],
          RendererTokens.table => [
            {
              'id': 'r1',
              'cells': {'c1': 'x'},
            },
          ],
          RendererTokens.form => [
            {'id': 'f1', 'label': 'Name', 'kind': 'text'},
          ],
          RendererTokens.markdown => [
            {'id': 'm1', 'text': '# Title'},
          ],
          _ => [
            {'id': 'n1', 'label': 'Node'},
          ],
        };
        final props = token == RendererTokens.table
            ? {
                'columns': [
                  {'id': 'c1', 'label': 'Col'},
                ],
              }
            : const <String, dynamic>{};

        await tester.pumpWidget(
          _wrap(
            SizedBox(
              height: 300,
              width: 400,
              child: Builder(
                builder: (context) => registry.build(
                  context,
                  token,
                  viewFor(nodes, props: props),
                ),
              ),
            ),
          ),
        );
        expect(
          find.byType(ComponentErrorBoundary),
          findsNothing,
          reason: 'renderer $token produced an error boundary',
        );
        expect(tester.takeException(), isNull, reason: token);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('an unknown renderer shows a diagnosable boundary', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                registry.build(context, 'native.hologram', viewFor(const [])),
          ),
        ),
      );
      expect(find.textContaining('no renderer registered'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('outline app bar renders actions outside placeholder content', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 300,
            width: 400,
            child: Builder(
              builder: (context) => registry.build(
                context,
                RendererTokens.outline,
                viewFor([
                  {
                    'id': 'state:none',
                    'label': 'Open a text file',
                    'role': 'placeholder',
                    'icon': 'material:code',
                  },
                  {
                    'id': 'open-expansion',
                    'label': 'Open in expansion area',
                    'role': 'appBarAction',
                    'appBarTitle': 'Outline',
                    'icon': 'material:vertical_split_outlined',
                  },
                ]),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Open a text file'), findsOneWidget);
      expect(find.byIcon(Icons.vertical_split_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.vertical_split_outlined));
      expect(harness.events.single.payload['nodeId'], 'open-expansion');
    });

    testWidgets('model nodes missing a required field are reported', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => registry.build(
              context,
              RendererTokens.outline,
              // outline rows need id + label; this one has no label.
              viewFor([
                {'id': 'n1'},
              ]),
            ),
          ),
        ),
      );
      expect(find.textContaining('nodes[0].label'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a loading view shows a spinner instead of empty content', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => registry.build(
              context,
              RendererTokens.outline,
              viewFor(const [], state: ViewState.loading),
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renderer config nodes become component props, not rows', (
      tester,
    ) async {
      final registry = NativePluginViewRegistry();
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 300,
            width: 400,
            child: Builder(
              builder: (context) => registry.build(
                context,
                RendererTokens.table,
                viewFor([
                  {
                    'id': 'row',
                    'cells': {'name': 'Pyrite'},
                  },
                  {
                    'id': '__view_config__',
                    'label': '',
                    'role': 'viewConfig',
                    'props': {
                      'columns': [
                        {'id': 'name', 'label': 'Name'},
                      ],
                    },
                  },
                ]),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Pyrite'), findsOneWidget);
      expect(find.text('__view_config__'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
