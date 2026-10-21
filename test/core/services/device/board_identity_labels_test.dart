import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/device/board_identity.dart';
import 'package:pyrite_ide/pages/device_tools/main.dart';

void main() {
  group('identifyUsbIdLabel', () {
    test('formats known ids as upper-case hex', () {
      expect(identifyUsbIdLabel(0x2E8A, 0x0005), '0x2E8A / 0x0005');
    });

    test('keeps unknown ids explicit instead of printing zeros', () {
      expect(identifyUsbIdLabel(null, null), '未知 / 未知');
      expect(identifyUsbIdLabel(0x2E8A, null), '0x2E8A / 未知');
    });
  });

  group('boardFamilyLabel', () {
    test('labels every family', () {
      for (final family in BoardFamily.values) {
        final label = boardFamilyLabel(family);
        expect(label, isNotEmpty, reason: family.name);
      }
      expect(boardFamilyLabel(BoardFamily.esp32s3), 'ESP32-S3');
      expect(boardFamilyLabel(BoardFamily.unknown), '未知');
    });
  });

  group('boardResetStrategyLabel', () {
    test('labels every strategy', () {
      for (final strategy in BoardResetStrategy.values) {
        expect(boardResetStrategyLabel(strategy), isNotEmpty);
      }
      expect(boardResetStrategyLabel(BoardResetStrategy.esp32), 'ESP32 自动复位');
    });
  });

  group('boardIdentityConfidenceLabel', () {
    test('labels every confidence', () {
      for (final confidence in BoardIdentityConfidence.values) {
        expect(boardIdentityConfidenceLabel(confidence), isNotEmpty);
      }
      expect(
        boardIdentityConfidenceLabel(BoardIdentityConfidence.exact),
        'USB VID/PID 精确匹配',
      );
    });
  });
}
