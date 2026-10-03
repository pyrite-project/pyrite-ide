/// Git repository service.
///
/// The libgit2-backed implementation is desktop/Android only; the Flutter Web
/// build resolves the default export, where Git is unavailable (like the
/// terminal) and the Git page shows its empty state.
export 'git_repository_service_web.dart'
    if (dart.library.io) 'git_repository_service_io.dart';
