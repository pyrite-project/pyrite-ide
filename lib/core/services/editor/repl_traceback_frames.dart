/// Parsing of Python/MicroPython traceback frames out of REPL output.
///
/// A MicroPython traceback names the script and the line it died on:
///
/// ```text
/// Traceback (most recent call last):
///   File "<stdin>", line 3, in <module>
///   File "main.py", line 12, in handler
/// NameError: name 'x' is not defined
/// ```
///
/// Only the frames that name a real file are usable. `<stdin>` means the code
/// came from the console and has no source to jump to, and `<string>` is the
/// same thing from an exec'd string, so both are dropped rather than offered as
/// a target that cannot open.
library;

/// One jumpable traceback frame.
typedef TracebackFrame = ({String file, int line});

/// The 0-based editor line that [frame] points at.
///
/// Python numbers source lines from 1, while the editor's line and column APIs
/// count from 0, so the raw [TracebackFrame.line] lands the caret one line
/// below the frame. Converting here keeps the convention change in one place
/// rather than at each call site that happens to open the editor.
int editorLineFor(TracebackFrame frame) => frame.line - 1;

/// Matches one traceback frame line.
///
/// The leading whitespace is required rather than optional: CPython and
/// MicroPython both indent frames by two spaces, and without it a line of
/// ordinary output that happens to start with `File "readme.txt", line 3`
/// would be offered as a jump target that goes nowhere.
final RegExp _framePattern = RegExp(
  r'^[ \t]+File "([^"]+)", line (\d+)',
  multiLine: true,
);

/// Extracts the jumpable frames from [output], in the order the traceback
/// lists them (innermost first).
///
/// Frames for `<stdin>` and `<string>` are dropped: they refer to code that was
/// typed into the console, which has no file behind it.
List<TracebackFrame> parseTracebackFrames(String output) {
  final frames = <TracebackFrame>[];
  for (final match in _framePattern.allMatches(output)) {
    final file = match.group(1)!.trim();
    if (file.isEmpty) continue;
    // The angle-bracket forms are CPython's spelling for "no source file".
    if (file.startsWith('<') && file.endsWith('>')) continue;
    final line = int.tryParse(match.group(2)!);
    if (line == null || line <= 0) continue;
    frames.add((file: file, line: line));
  }
  return frames;
}

/// True when [output] looks like it contains a traceback worth scanning.
///
/// Used to decide whether to look for frames at all, so the common case — a
/// program printing a result — does not run the scan on every append.
bool containsTraceback(String output) => output.contains('Traceback (most');

/// A frame together with the span of [output] it occupies.
///
/// The span covers the whole `File "main.py", line 12` so the entire reference
/// is the hit target, not just the digits the user is most likely to aim at.
typedef TracebackFrameRange = ({TracebackFrame frame, int start, int end});

/// Same frames as [parseTracebackFrames], with their offsets into [output].
///
/// Scans in one pass rather than searching for each parsed frame by name: the
/// same traceback repeats whenever the same code fails twice, and a per-frame
/// `indexOf` would map every repeat back onto the first occurrence — leaving
/// the later copies unhighlighted and untappable.
List<TracebackFrameRange> tracebackFrameRanges(String output) {
  final ranges = <TracebackFrameRange>[];
  for (final match in _framePattern.allMatches(output)) {
    final file = match.group(1)!.trim();
    if (file.isEmpty) continue;
    // The angle-bracket forms are CPython's spelling for "no source file".
    if (file.startsWith('<') && file.endsWith('>')) continue;
    final line = int.tryParse(match.group(2)!);
    if (line == null || line <= 0) continue;

    // The match starts at the indentation, so walk forward over the `File `
    // prefix to cover the whole reference as one hit target.
    var start = match.start;
    while (start < match.end &&
        (output[start] == ' ' || output[start] == '\t')) {
      start++;
    }
    ranges.add((frame: (file: file, line: line), start: start, end: match.end));
  }
  return ranges;
}
