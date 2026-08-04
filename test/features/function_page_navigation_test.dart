import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/context_key_service.dart';
import 'package:pyrite_ide/core/sdk/contribution_registry.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';
import 'package:pyrite_ide/features/function_page.dart';

PluginManifestV2 _manifest() => const PluginManifestV2(
  id: 'navigation',
  name: 'Navigation',
  version: '1.0.0',
  type: PluginType.ui,
  platforms: ['windows'],
  contributes: PluginContributions(
    navigationContainers: [
      PluginNavigationContainerContribution(
        id: 'navigation',
        title: 'Plugin Navigation',
        icon: PluginIconReference.material('extension_outlined'),
      ),
    ],
  ),
);

void main() {
  testWidgets('NavigationRail and Drawer expose plugin containers', (
    tester,
  ) async {
    final context = ContextKeyService();
    final registry = ContributionRegistry(context);
    registry.registerPlugin(_manifest());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contributionRegistryProvider.overrideWith((ref) => registry),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) => Row(
                children: [
                  SizedBox(
                    width: 180,
                    height: 600,
                    child: NavigationRail(
                      destinations: pluginNavigationRailDestinations(ref),
                      selectedIndex: null,
                      onDestinationSelected: (_) {},
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    height: 600,
                    child: NavigationDrawer(
                      children: pluginNavigationDrawerDestinations(ref),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Plugin Navigation'), findsNWidgets(2));
    registry.unregisterPlugin('navigation');
    await tester.pump();
    expect(find.text('Plugin Navigation'), findsNothing);
  });
}
