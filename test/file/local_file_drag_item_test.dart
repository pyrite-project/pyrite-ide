import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() {
  test('local file drag item provides a file URI', () {
    final item = createLocalFileDragItem(<String>['/workspace/main.py']);

    final encodedData = item.data.single as EncodedData;
    final representation = encodedData.representations.single as dynamic;

    expect(representation.data, isNot('/workspace/main.py'));
    expect(representation.data.toString(), contains('file:'));
  });
}
