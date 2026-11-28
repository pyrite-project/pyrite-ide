import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/window_placement.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';

void main() {
  late Directory tempDir;
  late File appFile;
  late AppPersistence persistence;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_persistence_test_');
    appFile = File('${tempDir.path}/app.json');
    persistence = AppPersistence(fileResolver: () async => appFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Map<String, dynamic>> readRawJson() async {
    return jsonDecode(await appFile.readAsString()) as Map<String, dynamic>;
  }

  test('load returns null when no file exists yet', () async {
    expect(await persistence.load(), isNull);
  });

  test('save and load round-trip window placement', () async {
    const placement = WindowPlacement(
      bounds: Rect.fromLTWH(120, 80, 1280, 720),
      maximized: true,
    );

    await persistence.save(
      AppPersistedData(themeMode: 'dark', windowPlacement: placement),
    );

    final raw = await readRawJson();
    expect(raw['window'], {
      'x': 120.0,
      'y': 80.0,
      'width': 1280.0,
      'height': 720.0,
      'maximized': true,
    });

    final loaded = await persistence.load();
    expect(loaded, isNotNull);
    expect(loaded!.themeMode, 'dark');
    expect(loaded.windowPlacement, placement);
  });

  test('fromJson is backward compatible without a window key', () async {
    await appFile.writeAsString(
      jsonEncode({'themeMode': 'light', 'welcomeCompleted': true}),
    );

    final loaded = await persistence.load();
    expect(loaded, isNotNull);
    expect(loaded!.themeMode, 'light');
    expect(loaded.welcomeCompleted, isTrue);
    expect(loaded.windowPlacement, isNull);
    expect(loaded.activeLocale, 'zh-CN');
  });

  test(
    'invalid persisted window entries are dropped, other data is kept',
    () async {
      for (final window in <Object?>[
        null,
        'not-a-window',
        {'x': 0, 'y': 0, 'width': 100, 'height': 100},
      ]) {
        await appFile.writeAsString(
          jsonEncode({'themeMode': 'dark', 'window': window}),
        );

        final loaded = await persistence.load();
        expect(loaded, isNotNull, reason: 'window: $window');
        expect(loaded!.themeMode, 'dark', reason: 'window: $window');
        expect(loaded.windowPlacement, isNull, reason: 'window: $window');
      }
    },
  );

  group('patch', () {
    test('creates the file when it does not exist', () async {
      await persistence.patch({'welcomeCompleted': true});

      expect(await appFile.exists(), isTrue);
      final raw = await readRawJson();
      expect(raw, {'welcomeCompleted': true});
    });

    test('merges into the existing file without dropping known keys', () async {
      const placement = WindowPlacement(bounds: Rect.fromLTWH(0, 0, 1280, 800));
      await persistence.save(
        AppPersistedData(
          themeMode: 'dark',
          activeLocale: 'en-US',
          windowPlacement: placement,
        ),
      );

      await persistence.patch({'welcomeCompleted': true});

      final loaded = await persistence.load();
      expect(loaded, isNotNull);
      expect(loaded!.welcomeCompleted, isTrue);
      expect(loaded.themeMode, 'dark');
      expect(loaded.activeLocale, 'en-US');
      expect(loaded.windowPlacement, placement);
    });

    test('preserves unknown keys already present in the file', () async {
      await appFile.writeAsString(
        jsonEncode({'themeMode': 'light', 'futureSetting': 42}),
      );

      await persistence.patch({'welcomeCompleted': true});

      final raw = await readRawJson();
      expect(raw['themeMode'], 'light');
      expect(raw['futureSetting'], 42);
      expect(raw['welcomeCompleted'], isTrue);
    });

    test('overwrites changed keys', () async {
      await persistence.save(
        AppPersistedData(themeMode: 'dark', welcomeCompleted: false),
      );

      await persistence.patch({'welcomeCompleted': true});

      expect((await persistence.load())?.welcomeCompleted, isTrue);
    });

    test('recovers from a malformed existing file', () async {
      await appFile.writeAsString('{not valid json');

      await persistence.patch({'welcomeCompleted': true});

      final raw = await readRawJson();
      expect(raw, {'welcomeCompleted': true});
    });
  });
}
