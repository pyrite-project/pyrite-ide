/// Native file-dialog bridge.
///
/// Native platforms use `file_selector`; the web build resolves the default
/// export with File System Access API implementations that keep the same
/// call sites working (open file / new file / save to disk).
export 'web/web_file_dialogs_web.dart'
    if (dart.library.io) 'web_file_dialogs_io.dart';
