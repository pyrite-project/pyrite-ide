import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/plugins/widgets/media.dart';
import 'package:pyrite_ide/pages/plugins/widgets/rfw_lib.dart';
import 'package:rfw/formats.dart' as formats;
import 'package:rfw/rfw.dart' as rfw;
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as video_platform;

void main() {
  testWidgets('Pyrite core Image loads an absolute Windows file path', (
    WidgetTester tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('pyrite_image_');
    final imageFile = File(
      '${directory.path}${Platform.pathSeparator}pixel.png',
    );
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    addTearDown(() {
      PaintingBinding.instance.imageCache.clear();
      directory.deleteSync(recursive: true);
    });

    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    runtime.update(
      rfw.LibraryName(<String>['core', 'widgets']),
      createPyriteCoreWidgets(),
    );
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.widgets;
import core.material;
widget root = Image(
  source: ${jsonEncode(imageFile.path)},
  sourceType: "file",
  width: 80.0,
  height: 40.0,
  fit: "cover",
  alignment: {"x": 1.0, "y": 0.0},
  filterQuality: "high",
  gaplessPlayback: true,
  isAntiAlias: true,
  semanticLabel: "Local preview"
);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: rfw.RemoteWidget(
          runtime: runtime,
          data: rfw.DynamicContent(),
          widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
          onEvent: (_, _) {},
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect((image.image as FileImage).file.path, imageFile.path);
    expect(image.width, 80);
    expect(image.height, 40);
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.centerRight);
    expect(image.filterQuality, FilterQuality.high);
    expect(image.gaplessPlayback, isTrue);
    expect(image.isAntiAlias, isTrue);
    expect(image.semanticLabel, 'Local preview');
  });

  testWidgets('Pyrite core Image forwards scale to asset images', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    runtime.update(
      rfw.LibraryName(<String>['core', 'widgets']),
      createPyriteCoreWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.widgets;
widget root = Image(
  source: "assets/example.png",
  sourceType: "asset",
  scale: 3.0,
  package: "example_package"
);
'''),
    );

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _MemoryAssetBundle(),
        child: MaterialApp(
          home: rfw.RemoteWidget(
            runtime: runtime,
            data: rfw.DynamicContent(),
            widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
            onEvent: (_, _) {},
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ExactAssetImage>());
    final provider = image.image as ExactAssetImage;
    expect(provider.assetName, 'assets/example.png');
    expect(provider.scale, 3);
    expect(provider.package, 'example_package');
  });

  testWidgets('display widgets decode values and forward events', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    String? eventName;
    formats.DynamicMap? eventArguments;
    runtime.update(
      rfw.LibraryName(<String>['core', 'widgets']),
      createPyriteCoreWidgets(),
    );
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.widgets;
import core.material;
widget root = ListView(children: [
  Tooltip(
    message: "Details",
    waitDuration: 150,
    showDuration: 1200,
    exitDuration: 75,
    preferBelow: false,
    triggerMode: "tap",
    onTriggered: event "tooltipTriggered" {},
    child: Text(text: "Hover target")
  ),
  Chip(
    label: Text(text: "Stable"),
    deleteIcon: Icon(icon: 0xe872, fontFamily: "MaterialIcons"),
    onDeleted: event "chipDeleted" {},
    backgroundColor: 0xffe3f2fd,
    deleteIconColor: 0xff1565c0,
    tooltip: "Remove",
    elevation: 2.0,
    autofocus: true
  ),
  ExpansionTile(
    title: Text(text: "Advanced"),
    subtitle: Text(text: "Options"),
    initiallyExpanded: true,
    maintainState: true,
    controlAffinity: "leading",
    onExpansionChanged: event "expansionChanged" {},
    children: [Text(text: "Expanded content")]
  ),
  DropdownButton(
    value: "alpha",
    onChanged: event "dropdownChanged" {},
    items: [
      {"value": "alpha", "label": "Alpha"},
      {"value": "beta", "label": "Beta", "enabled": false}
    ],
    iconSize: 28.0,
    isDense: true,
    isExpanded: true,
    dropdownColor: 0xfffafafa
  )
]);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: rfw.RemoteWidget(
            runtime: runtime,
            data: rfw.DynamicContent(),
            widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
            onEvent: (name, arguments) {
              eventName = name;
              eventArguments = arguments;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip).first);
    expect(tooltip.message, 'Details');
    expect(tooltip.waitDuration, const Duration(milliseconds: 150));
    expect(tooltip.showDuration, const Duration(milliseconds: 1200));
    expect(tooltip.exitDuration, const Duration(milliseconds: 75));
    expect(tooltip.preferBelow, isFalse);
    expect(tooltip.triggerMode, TooltipTriggerMode.tap);
    tooltip.onTriggered?.call();
    expect(eventName, 'tooltipTriggered');
    expect(eventArguments, <String, Object?>{});

    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, const Color(0xffe3f2fd));
    expect(chip.deleteIconColor, const Color(0xff1565c0));
    expect(chip.deleteButtonTooltipMessage, 'Remove');
    expect(chip.elevation, 2);
    expect(chip.autofocus, isTrue);
    chip.onDeleted?.call();
    expect(eventName, 'chipDeleted');
    expect(eventArguments, <String, Object?>{});

    final expansionTile = tester.widget<ExpansionTile>(
      find.byType(ExpansionTile),
    );
    expect(expansionTile.initiallyExpanded, isTrue);
    expect(expansionTile.maintainState, isTrue);
    expect(expansionTile.controlAffinity, ListTileControlAffinity.leading);
    expect(expansionTile.children, hasLength(1));
    expansionTile.onExpansionChanged?.call(false);
    expect(eventName, 'expansionChanged');
    expect(eventArguments, <String, Object?>{'value': false});

    final dropdown = tester.widget<DropdownButton<Object>>(
      find.byWidgetPredicate((widget) => widget is DropdownButton<Object>),
    );
    expect(dropdown.value, 'alpha');
    expect(dropdown.items, hasLength(2));
    expect(dropdown.items![1].enabled, isFalse);
    expect(dropdown.iconSize, 28);
    expect(dropdown.isDense, isTrue);
    expect(dropdown.isExpanded, isTrue);
    expect(dropdown.dropdownColor, const Color(0xfffafafa));
    dropdown.onChanged?.call('beta');
    expect(eventName, 'dropdownChanged');
    expect(eventArguments, <String, Object?>{'value': 'beta'});
  });

  testWidgets('VideoPlayer configures and disposes a local file controller', (
    WidgetTester tester,
  ) async {
    final originalPlatform = video_platform.VideoPlayerPlatform.instance;
    final fakePlatform = _FakeVideoPlayerPlatform();
    video_platform.VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      video_platform.VideoPlayerPlatform.instance = originalPlatform;
    });

    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.material;
widget root = VideoPlayer(
  source: "C:/media/demo.mp4",
  sourceType: "file",
  autoplay: true,
  looping: true,
  muted: true,
  showControls: true,
  fit: "cover",
  width: 320.0,
  height: 180.0
);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: rfw.RemoteWidget(
            runtime: runtime,
            data: rfw.DynamicContent(),
            widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
            onEvent: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final player = tester.widget<RfwVideoPlayer>(find.byType(RfwVideoPlayer));
    expect(player.source, 'C:/media/demo.mp4');
    expect(player.sourceType, 'file');
    expect(player.autoplay, isTrue);
    expect(player.looping, isTrue);
    expect(player.muted, isTrue);
    expect(player.showControls, isTrue);
    expect(player.fit, BoxFit.cover);
    expect(fakePlatform.dataSources, hasLength(1));
    expect(
      fakePlatform.dataSources.single.sourceType,
      video_platform.DataSourceType.file,
    );
    expect(fakePlatform.dataSources.single.uri, contains('demo.mp4'));
    expect(fakePlatform.loopingValues, contains(true));
    expect(fakePlatform.volumeValues, contains(0));
    expect(fakePlatform.calls, contains('play'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fakePlatform.disposedPlayerIds, contains(0));
  });

  testWidgets('VideoPlayer contains malformed network source errors', (
    WidgetTester tester,
  ) async {
    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.material;
widget root = VideoPlayer(
  source: "http://[invalid",
  sourceType: "network"
);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: rfw.RemoteWidget(
          runtime: runtime,
          data: rfw.DynamicContent(),
          widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
          onEvent: (_, _) {},
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('VideoPlayer disposes a controller after initialization fails', (
    WidgetTester tester,
  ) async {
    final originalPlatform = video_platform.VideoPlayerPlatform.instance;
    final fakePlatform = _FakeVideoPlayerPlatform(failInitialization: true);
    video_platform.VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      video_platform.VideoPlayerPlatform.instance = originalPlatform;
    });

    final runtime = rfw.Runtime();
    final pageName = rfw.LibraryName(<String>['test']);
    runtime.update(
      rfw.LibraryName(<String>['core', 'material']),
      createPyriteMaterialWidgets(),
    );
    runtime.update(
      pageName,
      formats.parseLibraryFile('''
import core.material;
widget root = VideoPlayer(
  source: "C:/media/broken.mp4",
  sourceType: "file"
);
'''),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: rfw.RemoteWidget(
          runtime: runtime,
          data: rfw.DynamicContent(),
          widget: rfw.FullyQualifiedWidgetName(pageName, 'root'),
          onEvent: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(fakePlatform.disposedPlayerIds, contains(0));
  });
}

class _MemoryAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  }
}

class _FakeVideoPlayerPlatform extends video_platform.VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.failInitialization = false});

  final bool failInitialization;
  final List<String> calls = <String>[];
  final List<video_platform.DataSource> dataSources =
      <video_platform.DataSource>[];
  final List<bool> loopingValues = <bool>[];
  final List<double> volumeValues = <double>[];
  final List<int> disposedPlayerIds = <int>[];
  final Map<int, StreamController<video_platform.VideoEvent>> _events =
      <int, StreamController<video_platform.VideoEvent>>{};
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int?> createWithOptions(
    video_platform.VideoCreationOptions options,
  ) async {
    calls.add('create');
    final playerId = _nextPlayerId++;
    final events = StreamController<video_platform.VideoEvent>();
    _events[playerId] = events;
    dataSources.add(options.dataSource);
    if (failInitialization) {
      events.addError(
        PlatformException(
          code: 'video_error',
          message: 'video initialization failed',
        ),
      );
    } else {
      events.add(
        video_platform.VideoEvent(
          eventType: video_platform.VideoEventType.initialized,
          duration: Duration(seconds: 10),
          size: Size(1920, 1080),
        ),
      );
    }
    return playerId;
  }

  @override
  Stream<video_platform.VideoEvent> videoEventsFor(int playerId) {
    return _events[playerId]!.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('setLooping');
    loopingValues.add(looping);
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('setVolume');
    volumeValues.add(volume);
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return Duration.zero;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo');
  }

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    disposedPlayerIds.add(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Widget buildView(int playerId) {
    return ColoredBox(key: ValueKey<int>(playerId), color: Colors.black);
  }
}
