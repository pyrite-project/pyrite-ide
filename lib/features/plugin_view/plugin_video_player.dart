import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as video;

/// Host-owned native video player for the `Video` plugin component.
///
/// Replaces the former RFW-coupled media widget: playback is driven directly by
/// `video_player`, and the exposed [PluginVideoPlayerState] methods implement
/// the `VideoController` contract (play/pause/seek/volume/speed/loop/fullscreen)
/// without any RFW dependency.
class PluginVideoPlayer extends StatefulWidget {
  const PluginVideoPlayer({
    super.key,
    required this.source,
    required this.sourceType,
    this.package,
    this.autoplay = false,
    this.looping = false,
    this.muted = false,
    this.showControls = true,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  final String source;
  final String sourceType;
  final String? package;
  final bool autoplay;
  final bool looping;
  final bool muted;
  final bool showControls;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<PluginVideoPlayer> createState() => PluginVideoPlayerState();
}

class PluginVideoPlayerState extends State<PluginVideoPlayer> {
  video.VideoPlayerController? _controller;
  bool _initialized = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _replaceController();
  }

  @override
  void didUpdateWidget(PluginVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.sourceType != widget.sourceType ||
        oldWidget.package != widget.package) {
      _replaceController();
      return;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (oldWidget.looping != widget.looping) {
      unawaited(controller.setLooping(widget.looping));
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(controller.setVolume(widget.muted ? 0.0 : 1.0));
    }
    if (oldWidget.autoplay != widget.autoplay) {
      unawaited(widget.autoplay ? controller.play() : controller.pause());
    }
  }

  void _replaceController() {
    final generation = ++_generation;
    final previousController = _controller;
    if (previousController != null) {
      unawaited(previousController.dispose());
    }

    _controller = null;
    _initialized = false;
    _error = null;
    if (widget.source.isEmpty) {
      _error = ArgumentError.value(
        widget.source,
        'source',
        'must not be empty',
      );
      return;
    }

    late final video.VideoPlayerController controller;
    try {
      controller = _createController();
    } catch (error) {
      _error = error;
      return;
    }
    _controller = controller;
    unawaited(_initializeController(controller, generation));
  }

  video.VideoPlayerController _createController() {
    switch (widget.sourceType) {
      case 'network':
        return video.VideoPlayerController.networkUrl(Uri.parse(widget.source));
      case 'asset':
        return video.VideoPlayerController.asset(
          widget.source,
          package: widget.package,
        );
      case 'file':
      default:
        return video.VideoPlayerController.file(_fileFromSource(widget.source));
    }
  }

  Future<void> _initializeController(
    video.VideoPlayerController controller,
    int generation,
  ) async {
    try {
      await controller.initialize();
      if (!_isCurrent(controller, generation)) {
        return;
      }
      await controller.setLooping(widget.looping);
      await controller.setVolume(widget.muted ? 0.0 : 1.0);
      if (widget.autoplay) {
        await controller.play();
      }
      if (_isCurrent(controller, generation)) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (error) {
      if (_isCurrent(controller, generation)) {
        _controller = null;
        unawaited(controller.dispose());
        setState(() {
          _error = error;
        });
      }
    }
  }

  bool _isCurrent(video.VideoPlayerController controller, int generation) {
    return mounted &&
        generation == _generation &&
        identical(controller, _controller);
  }

  /// The current playback state as a plugin-facing map (`VideoController.get_state`).
  Map<String, dynamic> get playbackState {
    final value = _controller?.value;
    return <String, dynamic>{
      'isInitialized': value?.isInitialized ?? false,
      'isPlaying': value?.isPlaying ?? false,
      'positionMs': value?.position.inMilliseconds ?? 0,
      'durationMs': value?.duration.inMilliseconds ?? 0,
      'volume': value?.volume ?? 1.0,
      'speed': value?.playbackSpeed ?? 1.0,
      'isLooping': value?.isLooping ?? false,
      'hasError': _error != null,
    };
  }

  Future<void> play() => _controller?.play() ?? Future.value();
  Future<void> pause() => _controller?.pause() ?? Future.value();
  Future<void> seekTo(Duration position) =>
      _controller?.seekTo(position) ?? Future.value();
  Future<void> setVolume(double volume) =>
      _controller?.setVolume(volume) ?? Future.value();
  Future<void> setPlaybackSpeed(double speed) =>
      _controller?.setPlaybackSpeed(speed) ?? Future.value();
  Future<void> setLooping(bool looping) =>
      _controller?.setLooping(looping) ?? Future.value();

  NavigatorState? _fullscreenNavigator;

  Future<void> enterFullscreen() async {
    final controller = _controller;
    if (!mounted || controller == null || !_initialized) return;
    final navigator = Navigator.of(context);
    _fullscreenNavigator = navigator;
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => _FullscreenPlayer(
          controller: controller,
          onClosed: () => _fullscreenNavigator = null,
        ),
      ),
    );
  }

  void exitFullscreen() {
    _fullscreenNavigator?.pop();
    _fullscreenNavigator = null;
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final aspectRatio = controller?.value.isInitialized ?? false
        ? controller!.value.aspectRatio
        : 16 / 9;

    Widget child;
    if (_error != null) {
      child = const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.error_outline, color: Colors.white70)),
      );
    } else if (!_initialized || controller == null) {
      child = const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      child = _buildInitializedPlayer(controller);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AspectRatio(aspectRatio: aspectRatio, child: child),
    );
  }

  Widget _buildInitializedPlayer(video.VideoPlayerController controller) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = controller.value.size;
              return FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: video.VideoPlayer(controller),
                ),
              );
            },
          ),
        ),
        if (widget.showControls) _buildControls(controller),
      ],
    );
  }

  Widget _buildControls(video.VideoPlayerController controller) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ColoredBox(
        color: Colors.black54,
        child: ValueListenableBuilder<video.VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            return Row(
              children: <Widget>[
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  color: Colors.white,
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    unawaited(
                      value.isPlaying ? controller.pause() : controller.play(),
                    );
                  },
                ),
                Expanded(
                  child: video.VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                IconButton(
                  tooltip: value.volume == 0 ? 'Unmute' : 'Mute',
                  color: Colors.white,
                  icon: Icon(
                    value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  ),
                  onPressed: () {
                    unawaited(
                      controller.setVolume(value.volume == 0 ? 1.0 : 0.0),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

File _fileFromSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri?.scheme.toLowerCase() == 'file') {
    return File.fromUri(uri!);
  }
  return File(source);
}

class _FullscreenPlayer extends StatelessWidget {
  const _FullscreenPlayer({required this.controller, this.onClosed});

  final video.VideoPlayerController controller;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(child: video.VideoPlayer(controller)),
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: 'Close',
                  color: Colors.white,
                  icon: const Icon(Icons.fullscreen_exit),
                  onPressed: () {
                    onClosed?.call();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
