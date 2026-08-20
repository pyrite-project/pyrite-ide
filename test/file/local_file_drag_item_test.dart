import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/pages/file/main.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() {
  test('local file drag item provides a file URI', () {
    final item = createLocalFileDragItem(<String>[
      '/workspace/main.py',
    ], platform: TargetPlatform.windows);

    final encodedData = item.data.single as EncodedData;
    final representation = encodedData.representations.single as dynamic;

    expect(representation.data, isNot('/workspace/main.py'));
    expect(representation.data.toString(), contains('file:'));
  });

  test('Android local file drag item does not expose a file URI', () {
    final item = createLocalFileDragItem(<String>[
      '/storage/emulated/0/main.py',
    ], platform: TargetPlatform.android);

    final encodedData = item.data.single as EncodedData;
    final representation = encodedData.representations.single as dynamic;

    expect(representation.data, '/storage/emulated/0/main.py');
    expect(representation.data.toString(), isNot(contains('file:')));
  });
}
