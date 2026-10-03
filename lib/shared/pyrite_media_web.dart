import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pyrite_ide/core/platform/pyrite_io.dart';
import 'package:video_player/video_player.dart' as video;
import 'package:web/web.dart' as web;

/// Renders [file] by decoding its bytes with [Image.memory]; returns
/// [fallback] when null or unreadable.
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
  return FutureBuilder<Uint8List?>(
    future: _readBytes(file),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return errorBuilder?.call(
              context,
              snapshot.error!,
              snapshot.stackTrace,
            ) ??
            fallback ??
            const SizedBox.shrink();
      }
      final bytes = snapshot.data;
      if (bytes == null) return fallback ?? const SizedBox.shrink();
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        color: color,
        colorBlendMode: colorBlendMode,
      );
    },
  );
}

Future<Uint8List?> _readBytes(File file) async {
  try {
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Synchronous image providers cannot read the virtual filesystem; callers
/// fall back to the widget-based helper or network images.
ImageProvider<Object>? fileImageProvider(File? file) => null;

/// Creates a video player controller for a file-backed [source] by loading
/// the bytes from the virtual filesystem and serving them through a blob URL.
Future<video.VideoPlayerController> fileVideoController(String source) async {
  final uri = Uri.tryParse(source);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'blob')) {
    return video.VideoPlayerController.contentUri(uri);
  }
  final file = uri?.scheme.toLowerCase() == 'file'
      ? File.fromUri(uri!)
      : File(source);
  final bytes = await file.readAsBytes();
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  return video.VideoPlayerController.contentUri(Uri.parse(url));
}
