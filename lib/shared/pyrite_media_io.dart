import 'package:flutter/widgets.dart';

import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:video_player/video_player.dart' as video;

/// Renders [file] with `Image.file`; returns [fallback] when null.
///
/// The facade [File] resolves to `dart:io`'s File on native builds, which is
/// what the dart:ui image APIs require.
Widget? fileImageWidget(
  File? file, {
  double? width,
  double? height,
  BoxFit? fit,
  Color? color,
  BlendMode? colorBlendMode,
  Widget? fallback,
  Widget? errorBuilder(BuildContext context, Object error, StackTrace? stack)?,
}) {
  if (file == null) return fallback;
  final ioFile = file as dynamic;
  return Image.file(
    ioFile,
    width: width,
    height: height,
    fit: fit,
    color: color,
    colorBlendMode: colorBlendMode,
    errorBuilder: errorBuilder == null
        ? null
        : (BuildContext context, Object error, StackTrace? stackTrace) =>
              errorBuilder(context, error, stackTrace ?? StackTrace.empty) ??
              const SizedBox.shrink(),
  );
}

/// Returns a [FileImage] for [file], or null.
ImageProvider<Object>? fileImageProvider(File? file) {
  if (file == null) return null;
  return FileImage(file as dynamic);
}

/// Creates a video player controller for a file-backed [source].
Future<video.VideoPlayerController> fileVideoController(String source) async {
  final uri = Uri.tryParse(source);
  final file = uri?.scheme.toLowerCase() == 'file'
      ? File.fromUri(uri!)
      : File(source);
  return video.VideoPlayerController.file(file as dynamic);
}
