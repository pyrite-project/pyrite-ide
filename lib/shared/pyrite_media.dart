/// Platform-aware media helpers for rendering file-backed images.
///
/// `dart:ui` image APIs ([Image.file], [FileImage]) require a real
/// `dart:io` [File], which cannot exist in a browser. Native platforms keep
/// the direct APIs; the web build decodes bytes from the virtual filesystem
/// asynchronously instead.
library;

export 'pyrite_media_web.dart' if (dart.library.io) 'pyrite_media_io.dart';
