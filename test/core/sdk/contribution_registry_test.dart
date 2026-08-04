import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

PluginManifestV2 _manifest(String id, {String? firstWhen, String? secondWhen}) {
  return PluginManifestV2(
    id: id,
    name: id,
    version: '1.0.0',
    type: PluginType.service,
    platforms: const ['windows'],
    contributes: PluginContributions(
      commands: [
        PluginCommandContribution(
          id: '$id.first',
          title: 'First',
          when: firstWhen,
        ),
        PluginCommandContribution(
          id: '$id.second',
          title: 'Second',
          when: secondWhen,
        ),
      ],
    ),
  );
}

void main() {
  test('restricted when expressions evaluate without executable code', () {
    final expression = WhenExpression.parse(
      "editor.hasDocument && editor.language == 'dart'",
    );
    expect(expression.dependencies, {'editor.hasDocument', 'editor.language'});
    expect(
      expression.evaluate({
        'editor.hasDocument': true,
        'editor.language': 'dart',
      }),
      isTrue,
    );
    expect(
      () => WhenExpression.parse('editor.language; throw evil()'),
      throwsFormatException,
    );
  });

  test('duplicate contribution IDs are rejected atomically', () {
    final context = ContextKeyService();
    final registry = ContributionRegistry(context);
    registry.registerPlugin(_manifest('first'));
    expect(
      () => registry.registerPlugin(_manifest('FIRST')),
      throwsA(isA<PluginManifestException>()),
    );
    expect(registry.pluginIds, {'first'});
    expect(registry.commands.byId('first.first'), isNotNull);
    registry.dispose();
    context.dispose();
  });

  test('failed replacement keeps the previous plugin snapshot', () {
    final context = ContextKeyService();
    final registry = ContributionRegistry(context);
    registry.registerPlugin(_manifest('example'));
    expect(
      () => registry.registerPlugin(
        _manifest('example', firstWhen: 'unknown.key'),
      ),
      throwsA(isA<PluginManifestException>()),
    );
    expect(registry.commands.byId('example.first'), isNotNull);
    registry.dispose();
    context.dispose();
  });

  test('context changes only reevaluate dependent contributions', () {
    final context = ContextKeyService();
    final registry = ContributionRegistry(context);
    registry.registerPlugin(
      _manifest(
        'example',
        firstWhen: 'editor.hasDocument',
        secondWhen: 'device.connected',
      ),
    );
    expect(registry.commands.visible, isEmpty);
    context.setValue('editor.hasDocument', true);
    expect(registry.lastContextEvaluationCount, 1);
    expect(registry.commands.visible.map((entry) => entry.value.id), [
      'example.first',
    ]);
    context.setValue('workspace.opened', true);
    expect(registry.lastContextEvaluationCount, 0);
    registry.unregisterPlugin('example');
    expect(registry.commands.all, isEmpty);
    registry.dispose();
    context.dispose();
  });
}
