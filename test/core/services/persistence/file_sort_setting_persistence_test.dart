import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/persistence/settings_persistence.dart';

void main() {
  test('file sort mode defaults to name and round-trips', () {
    expect(SettingsPersistedData.fromJson(const {}).fileSortMode, 'name');

    final data = SettingsPersistedData.fromJson({'fileSortMode': 'type'});

    expect(data.fileSortMode, 'type');
    expect(data.toJson()['fileSortMode'], 'type');
  });
}
