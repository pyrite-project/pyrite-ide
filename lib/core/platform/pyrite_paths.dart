/// Cross-platform application-storage paths.
///
/// Native platforms delegate to `package:path_provider`. Flutter Web serves
/// the app-support directory from an OPFS-backed mount (see [WebFs]) so all
/// persisted JSON state survives reloads.
export 'pyrite_paths_web.dart' if (dart.library.io) 'pyrite_paths_native.dart';
