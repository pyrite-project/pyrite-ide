import 'package:git2dart/git2dart.dart';

/// Initializes the libgit2 native library for this process.
Future<void> initializeGitNative() => PlatformSpecific.initialize();
