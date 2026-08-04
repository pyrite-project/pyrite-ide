import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/environment_provider.dart';

void main() {
  group('snapshot', () {
    test('serializes the fields a plugin lays itself out from', () {
      final notifier = EnvironmentNotifier(
        osOverride: 'android',
        isDesktopOverride: false,
      );
      notifier.update(layoutMode: LayoutMode.mobile, width: 412, height: 915);

      final json = notifier.snapshot.toJson();
      expect(json['os'], 'android');
      expect(json['isDesktopPlatform'], false);
      expect(json['layoutMode'], 'mobile');
      expect(json['width'], 412);
      expect(json['height'], 915);
    });

    test('is readable before any layout has been reported', () {
      // A plugin may call env.get() before its view mounts.
      final notifier = EnvironmentNotifier(osOverride: 'linux');
      expect(notifier.snapshot.os, 'linux');
      expect(notifier.snapshot.toJson()['layoutMode'], isNotNull);
    });
  });

  group('change notification', () {
    test('a layout mode change notifies after the debounce window', () async {
      final notifier = EnvironmentNotifier(
        debounce: const Duration(milliseconds: 10),
      );
      notifier.update(layoutMode: LayoutMode.desktop, width: 1400, height: 900);

      var notifications = 0;
      notifier.addListener(() => notifications++);

      notifier.update(layoutMode: LayoutMode.mobile, width: 400, height: 800);
      expect(notifications, 0, reason: 'debounced, not immediate');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications, 1);
      expect(notifier.snapshot.layoutMode, LayoutMode.mobile);
    });

    test('a resize within one mode does not wake plugins', () async {
      final notifier = EnvironmentNotifier(
        debounce: const Duration(milliseconds: 10),
      );
      notifier.update(layoutMode: LayoutMode.desktop, width: 1400, height: 900);

      var notifications = 0;
      notifier.addListener(() => notifications++);

      // A drag-resize: many frames, same mode.
      for (var width = 1400; width > 1000; width -= 20) {
        notifier.update(
          layoutMode: LayoutMode.desktop,
          width: width,
          height: 900,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifications, 0);
      // The width is still current for anyone who asks.
      expect(notifier.snapshot.width, 1020);
    });

    test(
      'a burst crossing a breakpoint collapses to one notification',
      () async {
        final notifier = EnvironmentNotifier(
          debounce: const Duration(milliseconds: 10),
        );
        notifier.update(
          layoutMode: LayoutMode.desktop,
          width: 1400,
          height: 900,
        );

        var notifications = 0;
        notifier.addListener(() => notifications++);

        // Dragging across two breakpoints in quick succession.
        notifier.update(layoutMode: LayoutMode.tablet, width: 700, height: 900);
        notifier.update(layoutMode: LayoutMode.mobile, width: 400, height: 900);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(notifications, 1);
        expect(notifier.snapshot.layoutMode, LayoutMode.mobile);
      },
    );

    test('theme and locale changes notify too', () async {
      final notifier = EnvironmentNotifier(
        debounce: const Duration(milliseconds: 10),
      );
      notifier.update(
        layoutMode: LayoutMode.desktop,
        width: 1400,
        height: 900,
        themeMode: 'light',
        locale: 'en',
      );

      var notifications = 0;
      notifier.addListener(() => notifications++);

      notifier.update(
        layoutMode: LayoutMode.desktop,
        width: 1400,
        height: 900,
        themeMode: 'dark',
        locale: 'zh-CN',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifications, 1);
      expect(notifier.snapshot.themeMode, 'dark');
      expect(notifier.snapshot.locale, 'zh-CN');
    });
  });
}
