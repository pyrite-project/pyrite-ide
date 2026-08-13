import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/code_forge_controller.dart';

void main() {
  test('backspace removes one indentation unit before code', () {
    expect(indentationBackspaceCount('        ', tabSize: 4), 4);
  });

  test('backspace removes a tab indentation unit', () {
    expect(indentationBackspaceCount('\t\t\t\t', tabSize: 4), 4);
  });
}
