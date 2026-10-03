/// Status-bar git summary.
///
/// The libgit2-backed implementation is desktop/Android only; the web build
/// resolves the default export, which reports no git repository.
export 'git_status_summary_provider_web.dart'
    if (dart.library.io) 'git_status_summary_provider_io.dart';
