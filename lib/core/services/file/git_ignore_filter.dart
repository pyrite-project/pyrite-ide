/// Git-ignore filtering for the file tree.
///
/// The libgit2-backed implementation is desktop/Android only; the web build
/// resolves the default export, which never reports ignored paths.
export 'git_ignore_filter_web.dart'
    if (dart.library.io) 'git_ignore_filter_io.dart';
