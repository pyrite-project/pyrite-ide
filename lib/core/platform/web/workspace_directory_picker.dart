/// Workspace directory picker.
///
/// The browser build resolves to the File System Access API implementation in
/// `web_fs_backend.dart`; native platforms have no browser handle to pick, so
/// they resolve to the stub below and never load `dart:js_interop`.
export 'workspace_directory_picker_web.dart'
    if (dart.library.io) 'workspace_directory_picker_io.dart';