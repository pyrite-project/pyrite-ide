import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:pyrite_ide/core/services/shortcut_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('findActivators', () {
    test('uses the platform modifier', () {
      final activators = findActivators();
      expect(activators, hasLength(1));
      if (usesCommandShortcut) {
        expect(activators.first.meta, isTrue);
        expect(activators.first.control, isFalse);
      } else {
        expect(activators.first.control, isTrue);
        expect(activators.first.meta, isFalse);
      }
      expect(activators.first.trigger, LogicalKeyboardKey.keyF);
    });
  });

  group('replaceActivators', () {
    test('adds Alt on command platforms to avoid Cmd+H conflicts', () {
      final activators = replaceActivators();
      expect(activators, hasLength(1));
      expect(activators.first.trigger, LogicalKeyboardKey.keyH);
      if (usesCommandShortcut) {
        expect(activators.first.meta, isTrue);
        expect(activators.first.alt, isTrue);
      } else {
        expect(activators.first.control, isTrue);
        expect(activators.first.alt, isFalse);
      }
    });
  });

  group('toggleCommentActivators', () {
    test('binds both control and meta variants of slash', () {
      final activators = toggleCommentActivators();
      expect(activators, hasLength(2));
      expect(
        activators.map((a) => a.trigger),
        everyElement(LogicalKeyboardKey.slash),
      );
      expect(activators.any((a) => a.control), isTrue);
      expect(activators.any((a) => a.meta), isTrue);
    });
  });

  group('shortcut labels', () {
    test('match the active platform modifier', () {
      if (usesCommandShortcut) {
        expect(findShortcutLabel(), 'Cmd+F');
        expect(replaceShortcutLabel(), 'Cmd+Alt+H');
        expect(toggleCommentShortcutLabel(), 'Cmd+/');
      } else {
        expect(findShortcutLabel(), 'Ctrl+F');
        expect(replaceShortcutLabel(), 'Ctrl+H');
        expect(toggleCommentShortcutLabel(), 'Ctrl+/');
      }
    });
  });

  group('stringToActivator roundtrip', () {
    test('roundtrips through activatorToString', () {
      const original = SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      );
      final restored = stringToActivator(activatorToString(original));
      expect(restored.trigger, original.trigger);
      expect(restored.control, original.control);
      expect(restored.shift, original.shift);
    });

    test('parses named keys and modifiers', () {
      final activator = stringToActivator('Ctrl+Enter');
      expect(activator.trigger, LogicalKeyboardKey.enter);
      expect(activator.control, isTrue);
      final cmd = stringToActivator('Command+F3');
      expect(cmd.trigger, LogicalKeyboardKey.f3);
      expect(cmd.meta, isTrue);
    });
  });
}
