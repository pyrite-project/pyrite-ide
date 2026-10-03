/// Desktop terminal sessions.
///
/// The PTY-backed implementation only exists on desktop platforms; the web
/// build resolves the default export, where the terminal stays disabled just
/// like on Android.
export 'desktop_terminal_provider_web.dart'
    if (dart.library.io) 'desktop_terminal_provider_io.dart';
