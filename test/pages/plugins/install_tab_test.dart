import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_provider.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_client.dart';
import 'package:pyrite_ide/core/sdk/plugin_registry_ledger.dart';
import 'package:pyrite_ide/core/sdk/trusted_plugin_origins.dart';
import 'package:pyrite_ide/pages/plugins/install_tab.dart';

const _intent = RegistryInstallIntent(
  pluginId: 'com.example.hello',
  version: '1.2.0',
  origin: 'https://forum.example',
);

PluginRegistryRelease _release({
  bool installable = true,
  PluginModeration moderation = const PluginModeration(level: 'none'),
}) => PluginRegistryRelease(
  pluginId: 'com.example.hello',
  name: 'Hello',
  version: '1.2.0',
  sha256: 'a' * 64,
  size: 4,
  type: 'ui',
  author: 'Ann',
  platforms: const ['windows'],
  permissions: const ['editor.read'],
  installable: installable,
  moderation: moderation,
);

class _Client extends PluginRegistryClient {
  _Client(this.release, {this.downloadError});

  final PluginRegistryRelease release;
  final Object? downloadError;

  @override
  Future<PluginRegistryRelease> fetchRelease(
    RegistryInstallIntent intent,
  ) async => release;

  @override
  Future<File> downloadPackage(
    RegistryInstallIntent intent,
    PluginRegistryRelease release,
    Directory directory,
  ) async {
    if (downloadError != null) throw downloadError!;
    await directory.create(recursive: true);
    return File('${directory.path}/p.pyrix')..writeAsStringSync('zip');
  }
}

class _Trusted extends TrustedPluginOrigins {
  _Trusted(this.trusted);

  final bool trusted;

  @override
  Future<Set<String>> load() async => trusted ? {_intent.origin} : {};

  @override
  Future<void> trust(String origin) async {}
}

String _t(I18nKey key) => key.fallback;

void main() {
  late Directory temp;
  late Directory support;
  late List<String> installed;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('install_tab_test');
    support = Directory.systemTemp.createTempSync('install_tab_ledger');
    installed = [];
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
    support.deleteSync(recursive: true);
  });

  Future<void> pumpTab(
    WidgetTester tester,
    _Client client, {
    bool trusted = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginInstallControllerProvider.overrideWith((ref, intent) {
            final controller = PluginInstallController(
              intent: intent,
              client: client,
              trustedOrigins: _Trusted(trusted),
              installPackage: (path) async {
                installed.add(path);
                return false;
              },
              ledger: PluginRegistryLedger(
                supportDirectory: () async => support,
              ),
              downloadRoot: () async => temp,
            );
            unawaited(controller.load());
            return controller;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PluginInstallTab(intent: _intent)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder installButton() =>
      find.widgetWithText(FilledButton, _t(I18nKey.pluginInstallAction));

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(installButton()).onPressed != null;

  testWidgets('shows the plugin, its permissions and the source', (
    tester,
  ) async {
    await pumpTab(tester, _Client(_release()));

    expect(find.textContaining('Hello'), findsWidgets);
    expect(find.text('editor.read'), findsOneWidget);
    expect(find.text('https://forum.example'), findsOneWidget);
    expect(enabled(tester), isTrue);
  });

  testWidgets('installs and reports success', (tester) async {
    await pumpTab(tester, _Client(_release()));

    // The download, ledger write and clean-up use real file I/O. Starting the
    // tap inside runAsync keeps the whole chain out of testWidgets' fake clock,
    // and the UI is polled until the chain has finished.
    await tester.runAsync(() => tester.tap(installButton()));
    for (var i = 0; i < 60; i++) {
      if (find.text(_t(I18nKey.pluginInstallDone)).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(installed, hasLength(1));
    expect(find.text(_t(I18nKey.pluginInstallDone)), findsOneWidget);
  });

  testWidgets('a new site must be trusted before installing', (tester) async {
    await pumpTab(tester, _Client(_release()), trusted: false);

    expect(find.text(_t(I18nKey.pluginInstallTrustSource)), findsOneWidget);
    expect(enabled(tester), isFalse);

    await tester.tap(find.text(_t(I18nKey.pluginInstallTrustSource)));
    await tester.pump();

    expect(enabled(tester), isTrue);
  });

  testWidgets('a high severity advisory must be acknowledged', (tester) async {
    await pumpTab(
      tester,
      _Client(
        _release(
          moderation: const PluginModeration(
            level: 'advisory',
            severity: 'high',
            message: 'Reads files outside the workspace',
          ),
        ),
      ),
    );

    expect(find.text('Reads files outside the workspace'), findsOneWidget);
    expect(
      find.textContaining(_t(I18nKey.pluginInstallSeverityHigh)),
      findsOneWidget,
    );
    expect(enabled(tester), isFalse);

    await tester.tap(find.text(_t(I18nKey.pluginInstallAcknowledge)));
    await tester.pump();

    expect(enabled(tester), isTrue);
  });

  testWidgets('a withdrawn release cannot be installed', (tester) async {
    await pumpTab(
      tester,
      _Client(
        _release(
          installable: false,
          moderation: const PluginModeration(
            level: 'withdrawn',
            message: 'Superseded',
          ),
        ),
      ),
    );

    expect(find.text('Superseded'), findsOneWidget);
    expect(find.text(_t(I18nKey.pluginInstallBlocked)), findsOneWidget);
    expect(enabled(tester), isFalse);
  });

  testWidgets('a tampered download is refused with a clear message', (
    tester,
  ) async {
    await pumpTab(
      tester,
      _Client(
        _release(),
        downloadError: const PluginRegistryException(
          PluginRegistryErrorCode.hashMismatch,
          'bad checksum',
        ),
      ),
    );

    await tester.tap(installButton());
    await tester.pumpAndSettle();

    expect(
      find.text(_t(I18nKey.pluginInstallErrorHashMismatch)),
      findsOneWidget,
    );
    expect(installed, isEmpty);
    expect(find.text(_t(I18nKey.pluginInstallRetry)), findsOneWidget);
  });
}
