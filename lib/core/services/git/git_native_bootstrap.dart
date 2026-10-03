/// Native git bootstrap.
///
/// libgit2 initialization only applies to native builds; the web build
/// resolves the default export, which is a no-op.
export 'git_native_bootstrap_web.dart'
    if (dart.library.io) 'git_native_bootstrap_io.dart';
