import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:rfw/rfw.dart' as rfw;
import 'package:video_player/video_player.dart' as video;

Widget buildImage(BuildContext context, rfw.DataSource source) {
  final imageSource = source.v<String>(<Object>['source']) ?? '';
  final provider = _imageProvider(context, source, imageSource);
  final image = ResizeImage.resizeIfNeeded(
    source.v<int>(<Object>['cacheWidth']),
    source.v<int>(<Object>['cacheHeight']),
    provider,
  );

  return Image(
    image: image,
    width: _double(source, <Object>['width']),
    height: _double(source, <Object>['height']),
    color: rfw.ArgumentDecoders.color(source, <Object>['color']),
    colorBlendMode: rfw.ArgumentDecoders.enumValue<BlendMode>(
      BlendMode.values,
      source,
      <Object>['colorBlendMode'],
    ),
    fit: rfw.ArgumentDecoders.enumValue<BoxFit>(BoxFit.values, source, <Object>[
      'fit',
    ]),
    alignment:
        rfw.ArgumentDecoders.alignment(source, <Object>['alignment']) ??
        Alignment.center,
    repeat:
        rfw.ArgumentDecoders.enumValue<ImageRepeat>(
          ImageRepeat.values,
          source,
          <Object>['repeat'],
        ) ??
        ImageRepeat.noRepeat,
    semanticLabel: source.v<String>(<Object>['semanticLabel']),
    excludeFromSemantics:
        source.v<bool>(<Object>['excludeFromSemantics']) ?? false,
    filterQuality:
        rfw.ArgumentDecoders.enumValue<FilterQuality>(
          FilterQuality.values,
          source,
          <Object>['filterQuality'],
        ) ??
        FilterQuality.medium,
    gaplessPlayback: source.v<bool>(<Object>['gaplessPlayback']) ?? false,
    isAntiAlias: source.v<bool>(<Object>['isAntiAlias']) ?? false,
  );
}

Widget buildVideoPlayer(BuildContext context, rfw.DataSource source) {
  return RfwVideoPlayer(
    source: source.v<String>(<Object>['source']) ?? '',
    sourceType: source.v<String>(<Object>['sourceType']) ?? 'file',
    package: source.v<String>(<Object>['package']),
    autoplay: source.v<bool>(<Object>['autoplay']) ?? false,
    looping: source.v<bool>(<Object>['looping']) ?? false,
    muted: source.v<bool>(<Object>['muted']) ?? false,
    showControls: source.v<bool>(<Object>['showControls']) ?? true,
    fit:
        rfw.ArgumentDecoders.enumValue<BoxFit>(BoxFit.values, source, <Object>[
          'fit',
        ]) ??
        BoxFit.contain,
    width: _double(source, <Object>['width']),
    height: _double(source, <Object>['height']),
  );
}

class RfwVideoPlayer extends StatefulWidget {
  const RfwVideoPlayer({
    super.key,
    required this.source,
    required this.sourceType,
    required this.package,
    required this.autoplay,
    required this.looping,
    required this.muted,
    required this.showControls,
    required this.fit,
    required this.width,
    required this.height,
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
  State<RfwVideoPlayer> createState() => _RfwVideoPlayerState();
}

class _RfwVideoPlayerState extends State<RfwVideoPlayer> {
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
  void didUpdateWidget(RfwVideoPlayer oldWidget) {
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

ImageProvider<Object> _imageProvider(
  BuildContext context,
  rfw.DataSource source,
  String imageSource,
) {
  final sourceType = source.v<String>(<Object>['sourceType']);
  final scale = _double(source, <Object>['scale']) ?? 1.0;

  if (sourceType == 'network' ||
      (sourceType == null && _isNetworkSource(imageSource))) {
    return NetworkImage(imageSource, scale: scale);
  }
  if (sourceType == 'file' ||
      (sourceType == null && _isFileSource(imageSource))) {
    return FileImage(_fileFromSource(imageSource), scale: scale);
  }
  return ExactAssetImage(
    imageSource,
    scale: scale,
    bundle: DefaultAssetBundle.of(context),
    package: source.v<String>(<Object>['package']),
  );
}

bool _isNetworkSource(String source) {
  final scheme = Uri.tryParse(source)?.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

bool _isFileSource(String source) {
  return Uri.tryParse(source)?.scheme.toLowerCase() == 'file' ||
      path.isAbsolute(source);
}

File _fileFromSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri?.scheme.toLowerCase() == 'file') {
    return File.fromUri(uri!);
  }
  return File(source);
}

double? _double(rfw.DataSource source, List<Object> key) {
  return source.v<double>(key) ?? source.v<int>(key)?.toDouble();
}
