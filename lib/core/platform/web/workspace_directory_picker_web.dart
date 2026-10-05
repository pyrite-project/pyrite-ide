import 'package:pyrite_ide/core/platform/web/web_fs_backend.dart';

/// Asks the browser for a workspace directory handle and returns its path.
Future<String?> pickWorkspaceDirectory() =>
    WebFs.instance.pickWorkspaceDirectory();