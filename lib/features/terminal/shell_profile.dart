/// Resolution of the desktop shell profile (executable, arguments, start
/// directory) configured on the terminal settings page.
///
/// Kept as plain functions with the filesystem checks injected, because the
/// interesting logic is the fallback order — an empty field must reproduce the
/// old behaviour exactly — and that is testable without starting a PTY.
library;

/// Splits a shell-argument string the way a login shell would split it.
///
/// Terminals store arguments as one editable string because a settings page
/// with one text field per argument is unusable. Single quotes keep everything
/// literal, double quotes allow `\"` and `\\` escapes, and a backslash outside
/// quotes escapes the next character. Unterminated quotes keep what was read so
/// far instead of dropping the rest: a half-typed quote in the settings dialog
/// must not silently delete the user's `-c` payload.
List<String> splitShellArguments(String raw) {
  final arguments = <String>[];
  final current = StringBuffer();
  var hasToken = false;
  String? quote;

  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];

    if (quote != null) {
      if (char == quote) {
        quote = null;
        continue;
      }
      if (quote == '"' && char == r'\' && i + 1 < raw.length) {
        final next = raw[i + 1];
        if (next == '"' || next == r'\') {
          current.write(next);
          i++;
          continue;
        }
      }
      current.write(char);
      continue;
    }

    if (char == '"' || char == "'") {
      quote = char;
      hasToken = true;
      continue;
    }
    if (char == r'\' && i + 1 < raw.length) {
      current.write(raw[i + 1]);
      hasToken = true;
      i++;
      continue;
    }
    if (char.trim().isEmpty) {
      if (hasToken) {
        arguments.add(current.toString());
        current.clear();
        hasToken = false;
      }
      continue;
    }
    current.write(char);
    hasToken = true;
  }

  if (hasToken) arguments.add(current.toString());
  return arguments;
}

/// A shell executable plus the arguments to launch it with.
typedef ShellCommand = ({String executable, List<String> arguments});

/// Picks the executable the terminal should launch.
///
/// [executableOverride] comes from the settings page. Blank means "not
/// configured", which must fall through to the platform default rather than
/// trying to spawn an empty path.
ShellCommand resolveShellCommand({
  required String executableOverride,
  required String arguments,
  required String fallbackExecutable,
  required List<String> fallbackArguments,
}) {
  final executable = executableOverride.trim();
  if (executable.isEmpty) {
    return (
      executable: fallbackExecutable,
      // The override's arguments are ignored as well: attaching them to a shell
      // the user did not choose would change the default launch line.
      arguments: fallbackArguments,
    );
  }
  return (executable: executable, arguments: splitShellArguments(arguments));
}

/// Picks the directory a new session starts in.
///
/// Order: the configured directory (if it still exists), then the workspace
/// root, then the process directory. A configured path that no longer exists
/// is skipped instead of failing the launch: directories get moved, and a
/// terminal that refuses to open because of a stale setting is worse than one
/// that starts in the workspace.
String resolveStartDirectory({
  required String configured,
  String? workspaceDirectory,
  String? currentDirectory,
  required bool Function(String directory) exists,
}) {
  final configuredDirectory = configured.trim();
  if (configuredDirectory.isNotEmpty && exists(configuredDirectory)) {
    return configuredDirectory;
  }
  final workspace = workspaceDirectory?.trim();
  if (workspace != null && workspace.isNotEmpty && exists(workspace)) {
    return workspace;
  }
  final current = currentDirectory?.trim();
  if (current != null && current.isNotEmpty) return current;
  return '.';
}
