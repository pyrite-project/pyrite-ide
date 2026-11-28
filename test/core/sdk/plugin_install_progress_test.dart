import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_manager_provider.dart';

void main() {
  // The notifier schedules a timer to clear the finished state; the test
  // binding must be initialised so timers are allowed, and each test disposes
  // the notifier to cancel it.
  TestWidgetsFlutterBinding.ensureInitialized();

  PluginInstallProgressNotifier createNotifier() {
    final notifier = PluginInstallProgressNotifier();
    addTearDown(notifier.dispose);
    return notifier;
  }

  group('PluginInstallProgressNotifier', () {
    test('begin starts at the extract stage with one slice of progress', () {
      final notifier = createNotifier();

      notifier.begin();

      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.stage, PluginInstallStage.extract);
      expect(notifier.state.failed, isFalse);
      expect(notifier.state.progress, closeTo(0.25, 0.001));
    });

    test('entering stages advances the bar in equal slices', () {
      final notifier = createNotifier();
      notifier.begin();

      notifier.enter(PluginInstallStage.validate);
      expect(notifier.state.progress, closeTo(0.5, 0.001));

      notifier.enter(PluginInstallStage.apply);
      expect(notifier.state.progress, closeTo(0.75, 0.001));

      notifier.enter(PluginInstallStage.start);
      expect(notifier.state.progress, closeTo(1.0, 0.001));
    });

    test('the plugin name is recorded once the manifest is parsed', () {
      final notifier = createNotifier();
      notifier.begin();

      notifier.setPluginName('demo_plugin');

      expect(notifier.state.pluginName, 'demo_plugin');
    });

    test('fail keeps the indicator active and marks it failed', () {
      final notifier = createNotifier();
      notifier.begin();

      notifier.fail();

      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.failed, isTrue);
    });

    test('complete clears the failed flag and clear resets to idle', () {
      final notifier = createNotifier();
      notifier.begin();
      notifier.fail();

      notifier.complete();
      expect(notifier.state.failed, isFalse);
      expect(notifier.state.isActive, isTrue);

      notifier.clear();
      expect(notifier.state.isActive, isFalse);
      expect(notifier.state.stage, isNull);
      expect(notifier.state.pluginName, isNull);
      expect(notifier.state.progress, isNull);
    });

    test('a new install does not inherit the previous failure or name', () {
      final notifier = createNotifier();
      notifier.begin();
      notifier.setPluginName('demo_plugin');
      notifier.fail();

      notifier.begin();

      expect(notifier.state.pluginName, isNull);
      expect(notifier.state.failed, isFalse);
      expect(notifier.state.stage, PluginInstallStage.extract);
    });
  });
}
