import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs [executable] and returns its stdout, or null when it cannot start,
/// exits non-zero or outlives [timeout] (it is killed then).
///
/// Port metadata is optional, so a slow or missing system tool must never
/// hold up the device list.
Future<String?> runForOutput(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    return null;
  }
  final stdout = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  unawaited(process.stderr.drain<void>());
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  if (exitCode != 0) return null;
  return stdout;
}
