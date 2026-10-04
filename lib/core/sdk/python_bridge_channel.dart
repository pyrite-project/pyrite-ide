/// Dart-Python byte channel factory.
///
/// The real channel is backed by `serious_python`'s native bridge on
/// desktop/Android. The web build resolves the default export, which cannot
/// open a channel (the Python runtime is unavailable there).
export 'python_bridge_channel_web.dart'
    if (dart.library.io) 'python_bridge_channel_io.dart';
