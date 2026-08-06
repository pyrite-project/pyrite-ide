import 'package:xterm/xterm.dart';

final Terminal repl = Terminal();
final TerminalController replController = TerminalController();

/// Host-owned sink for interactive REPL input. Serial and WebREPL transports
/// use this instead of competing to replace [Terminal.onOutput] in widgets.
void Function(String data)? replInputSink;

/// Host-owned device-output sink. When absent, output is rendered directly.
void Function(String data)? replOutputSink;

/// Host-owned clear action for the custom REPL surface.
void Function()? replClearSink;

/// Host-owned lifecycle hooks for IDE-triggered runs which write into REPL.
void Function()? replRunStartedSink;
void Function()? replRunFinishedSink;

void writeReplOutput(String data) {
  final sink = replOutputSink;
  if (sink != null) {
    sink(data);
  } else {
    repl.write(data);
  }
}

void beginReplRunOutput() => replRunStartedSink?.call();

void finishReplRunOutput() {
  final sink = replRunFinishedSink;
  if (sink != null) {
    sink();
  } else {
    repl.write('\r\n>>> ');
  }
}
