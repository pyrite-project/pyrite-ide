import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/plugin_view/plugin_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A minimal platform implementation so [PluginVideoPlayer] can initialize
/// without a real video backend.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;
    scheduleMicrotask(() {
      if (events.isClosed) return;
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(16, 9),
          rotationCorrection: 0,
        ),
      );
    });
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
}

void main() {
  late VideoPlayerPlatform originalPlatform;

  setUp(() {
    originalPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalPlatform;
  });

  Future<GlobalKey<PluginVideoPlayerState>> pumpPlayer(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<PluginVideoPlayerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginVideoPlayer(
            key: key,
            source: 'https://example.com/video.mp4',
            sourceType: 'network',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('a late exit_fullscreen does not pop the page after system back', (
    tester,
  ) async {
    final key = await pumpPlayer(tester);
    final state = key.currentState!;

    // enterFullscreen completes only when the route is popped, so the caller
    // (the plugin bridge) does not await it.
    unawaited(state.enterFullscreen());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    // Android system back pops the fullscreen route directly; the close button
    // never runs.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);

    // The plugin still holds the controller and may call exit_fullscreen after
    // the page is already gone. It must be a no-op, not a pop of the plugin
    // page underneath.
    state.exitFullscreen();
    await tester.pumpAndSettle();

    expect(find.byType(PluginVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('exit_fullscreen closes a fullscreen route that is still open', (
    tester,
  ) async {
    final key = await pumpPlayer(tester);
    final state = key.currentState!;

    unawaited(state.enterFullscreen());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    state.exitFullscreen();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
    expect(find.byType(PluginVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('the close button leaves the plugin page in place', (
    tester,
  ) async {
    final key = await pumpPlayer(tester);

    unawaited(key.currentState!.enterFullscreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.fullscreen_exit));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
    expect(find.byType(PluginVideoPlayer), findsOneWidget);

    // A second exit after the button closed the route is also a no-op.
    key.currentState!.exitFullscreen();
    await tester.pumpAndSettle();
    expect(find.byType(PluginVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
