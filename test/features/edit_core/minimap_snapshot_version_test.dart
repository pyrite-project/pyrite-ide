import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/features/edit_core/editor_language.dart';
import 'package:pyrite_ide/features/edit_core/editor_minimap.dart';

/// The minimap records its bar layer from a text snapshot taken before the
/// asynchronous pre-highlight, but must record the document version that
/// snapshot belongs to. Recording the version read after the await makes a
/// recording built from the old text claim the new version: the debounced
/// recompute the edit scheduled then sees "nothing changed" and returns,
/// leaving the map on stale bars until the next edit.
///
/// The fake controller swaps its text during the last `getLineText` of the
/// snapshot, which is the window the real await occupies.
void main() {
  testWidgets('an edit during the pre-highlight is recorded against its own '
      'version', (tester) async {
    final original = List.generate(12, (i) => 'old line $i');
    final updated = List.generate(12, (i) => 'new line $i');
    final controller = _SnapshotEditingController(original, nextLines: updated);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MinimapEditorShell(
            controller: controller,
            enabled: true,
            lineWrap: false,
            foreground: Colors.white,
            background: Colors.black,
            editorTheme: const {'root': TextStyle(color: Colors.white)},
            language: resolveEditorLanguage('sample.py').mode,
            baseTextStyle: const TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
            ),
            estimatedLineHeight: 16.8,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    // Let the initial recording land: its pre-highlight continuation runs on
    // microtasks, which the pump flushes.
    await tester.pump();
    final readsAfterInitialRecording = controller.reads;
    expect(
      readsAfterInitialRecording,
      greaterThanOrEqualTo(original.length),
      reason: 'the initial recording must have sampled the document',
    );

    // The edit notified during the snapshot; its recompute is debounced.
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      controller.reads,
      readsAfterInitialRecording,
      reason: 'the debounce has not expired yet',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(
      controller.reads,
      greaterThan(readsAfterInitialRecording),
      reason:
          'the debounced recompute must notice the recording was built from '
          'the pre-edit version and sample the new text',
    );
  });
}

/// A controller whose document changes while the minimap is sampling it.
class _SnapshotEditingController implements CodeForgeController {
  _SnapshotEditingController(this._lines, {required List<String> nextLines})
    : _nextLines = nextLines;

  List<String> _lines;
  List<String>? _nextLines;
  int _version = 0;
  int reads = 0;
  final List<VoidCallback> _listeners = [];

  @override
  double? editorLineHeight = 16.8;

  @override
  int get lineCount => _lines.length;

  @override
  int get documentVersion => _version;

  @override
  int? get firstVisibleLine => null;

  @override
  int? get visibleLineCount => null;

  @override
  String getLineText(int line) {
    reads++;
    final text = _lines[line];
    final next = _nextLines;
    // The sampling loop walks the window in order, so the last line is the
    // last read before the highlight await.
    if (next != null && line == _lines.length - 1) {
      _nextLines = null;
      _lines = next;
      _version++;
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    }
    return text;
  }

  @override
  void jumpToLine(int line) {}

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void dispose() => _listeners.clear();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not read by the minimap: $invocation');
}
