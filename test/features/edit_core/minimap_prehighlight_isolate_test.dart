import 'package:code_forge/code_forge/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';

/// Isolates the engine half of the minimap recording pipeline.
///
/// The minimap hands the whole document to
/// [SyntaxHighlighter.preHighlightLines]; with 50+ lines that runs on a
/// `compute` isolate. If that isolate never returns for some real-world
/// content, the highlighter's in-flight join makes every later call at the
/// same version await the same dead future forever — the minimap's recordings
/// then freeze at the last successful one, which is exactly the "map offset
/// from the code" report. This test times that call out at the engine level,
/// with the real Python grammar and realistic line content.
void main() {
  test(
    'preHighlightLines returns for a full document of realistic Python',
    () async {
      final language = resolveEditorLanguage('bridge.py');
      final lines = <String>[];
      for (var i = 0; i < 1166; i++) {
        lines.add(switch (i % 12) {
          0 => 'import asyncio',
          1 => 'class Bridge$i(BasePlugin):',
          2 => '    """Docstring for bridge $i with "nested quotes" inside."""',
          3 => '    clients: dict[str, Envelope] = {}',
          4 => '    async def send_all(self, envelope: Envelope) → None:',
          5 => '        if envelope.type ≠ "sdk.output.append":',
          6 =>
            '            self._log_internal(f"Sending: {envelope.type} at $i")',
          7 =>
            '            await self.transport.send(client, envelope.model_dump_json(by_alias=True))',
          8 => '        except TransportClosedError as e:',
          9 =>
            '            # comment $i — keep the connection alive  # noqa: E501',
          10 => "            self.queue.put_nowait([None, _STOP_MESSAGE])",
          _ =>
            '                on_error: Optional[Callable[[BaseException], Any]] = None,',
        });
      }
      final highlighter = SyntaxHighlighter(
        language: language.mode,
        editorTheme: const {
          'root': TextStyle(color: Color(0xFFD4D4D4)),
          'keyword': TextStyle(color: Color(0xFF569CD6)),
          'string': TextStyle(color: Color(0xFFCE9178)),
          'comment': TextStyle(color: Color(0xFF6A9955)),
          'number': TextStyle(color: Color(0xFFB5CEA8)),
        },
        baseTextStyle: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
      );
      highlighter.attachLineTextProvider((line) => lines[line]);
      addTearDown(highlighter.dispose);

      await highlighter
          .preHighlightLines(0, lines.length - 1, (line) => lines[line])
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => fail(
              'preHighlightLines never returned: the highlight isolate is '
              'stuck, and every later call at the same version joins it',
            ),
          );

      final span = highlighter.getLineSpan(900, lines[900]);
      expect(span, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'concurrent pre-highlight requests join within the join timeout',
    () async {
      final highlighter = _pythonHighlighter();
      final lines = List.generate(200, (i) => 'def f$i(): pass');
      var scans = 0;
      // 200 lines ≥ the 50-line threshold, so the request runs on a compute
      // isolate and stays in flight past these two synchronous calls. The
      // second call must join it: joining is what keeps overlapping callers
      // from stacking duplicate isolate round trips, and a joined caller never
      // rescans the lines (its getLineText is never invoked).
      final first = highlighter.preHighlightLines(0, 199, (line) {
        scans++;
        return lines[line];
      });
      final second = highlighter.preHighlightLines(0, 199, (line) {
        scans++;
        return lines[line];
      });
      await Future.wait([first, second]).timeout(const Duration(seconds: 30));
      expect(
        scans,
        200,
        reason:
            'the second call joined the first, rescanning '
            'nothing',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'an in-flight request past the join timeout is abandoned, not joined',
    () async {
      final highlighter = _pythonHighlighter();
      // A zero join window makes every later call stale: the only way the
      // pipeline can recover from a wedged isolate is for the next caller to
      // run its own request instead of awaiting the dead future forever.
      highlighter.preHighlightJoinTimeout = Duration.zero;
      final lines = List.generate(200, (i) => 'def f$i(): pass');
      var scans = 0;
      final first = highlighter.preHighlightLines(0, 199, (line) {
        scans++;
        return lines[line];
      });
      final second = highlighter.preHighlightLines(0, 199, (line) {
        scans++;
        return lines[line];
      });
      await Future.wait([first, second]).timeout(const Duration(seconds: 30));
      expect(
        scans,
        400,
        reason:
            'the second call must run its own request '
            'instead of joining the stale in-flight one',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

SyntaxHighlighter _pythonHighlighter() {
  return SyntaxHighlighter(
    language: resolveEditorLanguage('bridge.py').mode,
    editorTheme: const {
      'root': TextStyle(color: Color(0xFFD4D4D4)),
      'keyword': TextStyle(color: Color(0xFF569CD6)),
      'string': TextStyle(color: Color(0xFFCE9178)),
      'comment': TextStyle(color: Color(0xFF6A9955)),
    },
    baseTextStyle: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
  );
}
