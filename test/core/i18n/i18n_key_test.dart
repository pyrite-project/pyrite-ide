import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';

void main() {
  test('i18n keys are unique and have a non-empty fallback', () {
    final seen = <String>{};
    for (final key in I18nKey.values) {
      expect(
        key.key,
        isNotEmpty,
        reason: '${key.name} has an empty translation key',
      );
      expect(
        key.fallback,
        isNotEmpty,
        reason: '${key.name} has an empty fallback',
      );
      expect(
        seen.add(key.key),
        isTrue,
        reason: 'duplicate translation key ${key.key} (${key.name})',
      );
    }
  });
}
