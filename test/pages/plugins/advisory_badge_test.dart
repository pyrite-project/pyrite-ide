import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/sdk/plugin_advisory_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/pages/plugins/advisory_badge.dart';
import 'package:pyrite_ide/pages/plugins/moderation_banner.dart';

PluginAdvisory _advisory(
  String level, {
  String? severity,
  String? message,
  bool installable = true,
}) => PluginAdvisory(
  pluginId: 'a',
  version: '1.0.0',
  installable: installable,
  moderation: PluginModeration(
    level: level,
    severity: severity,
    message: message,
  ),
);

void main() {
  Future<void> pumpBadge(
    WidgetTester tester,
    Map<String, PluginAdvisory> advisories,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginAdvisoryProvider.overrideWith(
            (ref) =>
                PluginAdvisoryNotifier(installedPlugins: () => {})
                  ..state = PluginAdvisoryState(advisories: advisories),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PluginAdvisoryBadge(pluginId: 'a')),
        ),
      ),
    );
  }

  testWidgets('shows nothing for a plugin without a warning', (tester) async {
    await pumpBadge(tester, {'a': _advisory('none')});

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('shows nothing for a plugin the registry never mentioned', (
    tester,
  ) async {
    await pumpBadge(tester, {});

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('marks a security advisory as a warning with its message', (
    tester,
  ) async {
    await pumpBadge(tester, {
      'a': _advisory('advisory', severity: 'high', message: 'Reads files'),
    });

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      contains(I18nKey.pluginInstallSeverityHigh.fallback),
    );
    expect(
      tooltip.message,
      contains(I18nKey.pluginInstallLevelAdvisory.fallback),
    );
    expect(tooltip.message, contains('Reads files'));
  });

  testWidgets('marks a withdrawn release as a warning', (tester) async {
    await pumpBadge(tester, {
      'a': _advisory('withdrawn', installable: false, message: 'Broken'),
    });

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('shows a deprecation as a hint, not a warning', (tester) async {
    await pumpBadge(tester, {
      'a': _advisory('deprecated', message: 'Use Hello 2'),
    });

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  test('titles put the severity before the kind of notice', () {
    String translate(I18nKey key) => key.fallback;

    expect(
      pluginModerationTitleWith(
        translate,
        const PluginModeration(level: 'advisory', severity: 'critical'),
      ),
      '${I18nKey.pluginInstallSeverityCritical.fallback} · '
      '${I18nKey.pluginInstallLevelAdvisory.fallback}',
    );
    expect(
      pluginModerationTitleWith(
        translate,
        const PluginModeration(level: 'deprecated'),
      ),
      I18nKey.pluginInstallLevelDeprecated.fallback,
    );
    expect(
      pluginModerationTitleWith(
        translate,
        const PluginModeration(level: 'something-new'),
      ),
      'something-new',
    );
  });
}
