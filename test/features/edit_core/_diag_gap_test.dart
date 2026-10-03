import 'package:code_forge/code_forge/code_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gap logic', () {
    const source =
        'Some prose about deployment.\n\n'
        '```dart\n'
        'This method facilitates the export of the model:\n'
        '```\n';
    const code = 'This method facilitates the export of the model:\n';
    // ignore: avoid_print
    print('above=${codeBlockHasContentAbove(source, code)} below=${codeBlockHasContentBelow(source, code)} margin=${codeBlockMargin(source, code)}');
    const codeNoNl = 'This method facilitates the export of the model:';
    // ignore: avoid_print
    print('noNL above=${codeBlockHasContentAbove(source, codeNoNl)} margin=${codeBlockMargin(source, codeNoNl)}');
  });
}
