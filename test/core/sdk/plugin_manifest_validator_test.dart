import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_manifest.dart';

PluginManifestV2 _uiManifest({
  String pluginId = 'fixture',
  String? viewId,
  String renderer = 'native.form',
  PluginIconReference? icon,
  String? when,
  List<String>? activationEvents,
}) {
  final resolvedViewId = viewId ?? '$pluginId.home';
  return PluginManifestV2(
    id: pluginId,
    name: 'Fixture',
    version: '1.0.0',
    type: PluginType.ui,
    activationEvents: activationEvents ?? <String>['onView:$resolvedViewId'],
    contributes: PluginContributions(
      navigationContainers: [
        PluginNavigationContainerContribution(id: pluginId, title: 'Fixture'),
      ],
      views: [
        PluginViewContribution(
          id: resolvedViewId,
          container: pluginId,
          title: 'Home',
          renderer: renderer,
          icon: icon,
          when: when,
        ),
      ],
    ),
  );
}

Matcher _manifestError(String code) =>
    isA<PluginManifestException>().having((error) => error.code, 'code', code);

void main() {
  test('contribution IDs must use the plugin namespace', () {
    expect(
      () =>
          PluginManifestValidator().validate(_uiManifest(viewId: 'other.home')),
      throwsA(_manifestError(PluginManifestErrorCode.invalidContributionId)),
    );
  });

  test('plugin IDs reject platform-reserved path names', () {
    expect(
      () => PluginManifestValidator().validate(_uiManifest(pluginId: 'CON')),
      throwsA(_manifestError(PluginManifestErrorCode.invalidPluginId)),
    );
  });

  test('blank text rejects byte-order marks', () {
    const manifest = PluginManifestV2(
      id: 'fixture',
      name: '\uFEFF',
      version: '1.0.0',
      type: PluginType.service,
    );
    expect(
      () => PluginManifestValidator().validate(manifest),
      throwsA(_manifestError(PluginManifestErrorCode.invalidSchema)),
    );
  });

  test('global contribution conflicts are case insensitive', () {
    final candidate = _uiManifest(pluginId: 'Fixture');
    final installed = _uiManifest(pluginId: 'fixture');

    expect(
      () =>
          PluginManifestValidator().validateNoConflicts(candidate, [installed]),
      throwsA(_manifestError(PluginManifestErrorCode.contributionConflict)),
    );

    const serviceCandidate = PluginManifestV2(
      id: 'Alias',
      name: 'Alias',
      version: '1.0.0',
      type: PluginType.service,
    );
    const serviceInstalled = PluginManifestV2(
      id: 'alias',
      name: 'alias',
      version: '1.0.0',
      type: PluginType.service,
    );
    expect(
      () => PluginManifestValidator().validateNoConflicts(serviceCandidate, [
        serviceInstalled,
      ]),
      throwsA(_manifestError(PluginManifestErrorCode.contributionConflict)),
    );
  });

  test('unknown icons and activation targets have stable errors', () {
    expect(
      () => PluginManifestValidator().validate(
        _uiManifest(icon: const PluginIconReference.material('arbitrary-icon')),
      ),
      throwsA(_manifestError(PluginManifestErrorCode.unknownIcon)),
    );
    expect(
      () => PluginManifestValidator().validate(
        _uiManifest(activationEvents: const ['onView:fixture.missing']),
      ),
      throwsA(_manifestError(PluginManifestErrorCode.invalidActivationEvent)),
    );
  });

  test('renderer errors distinguish retired RFW from unknown names', () {
    expect(
      () => PluginManifestValidator().validate(
        _uiManifest(renderer: 'rfw.widget'),
      ),
      throwsA(_manifestError(PluginManifestErrorCode.rfwRendererUnsupported)),
    );
    expect(
      () => PluginManifestValidator().validate(
        _uiManifest(renderer: 'native.rfwatch'),
      ),
      throwsA(_manifestError(PluginManifestErrorCode.unknownRenderer)),
    );
  });

  test('custom capability catalogs are immutable snapshots', () {
    final renderers = {'native.custom'};
    final icons = {'custom-icon'};
    final keys = {'custom.enabled'};
    final validator = PluginManifestValidator(
      supportedRenderers: renderers,
      supportedIcons: icons,
      contextKeys: keys,
    );
    renderers.clear();
    icons.clear();
    keys.clear();

    validator.validate(
      _uiManifest(
        renderer: 'native.custom',
        icon: const PluginIconReference.material('custom-icon'),
        when: 'custom.enabled',
      ),
    );
  });

  test('configuration defaults must match their declared type', () {
    const manifest = PluginManifestV2(
      id: 'fixture',
      name: 'Fixture',
      version: '1.0.0',
      type: PluginType.service,
      contributes: PluginContributions(
        configuration: [
          PluginConfigurationContribution(
            id: 'fixture.count',
            title: 'Count',
            type: 'integer',
            defaultValue: true,
          ),
        ],
      ),
    );

    expect(
      () => PluginManifestValidator().validate(manifest),
      throwsA(_manifestError(PluginManifestErrorCode.invalidSchema)),
    );
  });

  test('configuration enum values must match their declared type', () {
    const manifest = PluginManifestV2(
      id: 'fixture',
      name: 'Fixture',
      version: '1.0.0',
      type: PluginType.service,
      contributes: PluginContributions(
        configuration: [
          PluginConfigurationContribution(
            id: 'fixture.count',
            title: 'Count',
            type: 'integer',
            enumValues: [null],
          ),
        ],
      ),
    );

    expect(
      () => PluginManifestValidator().validate(manifest),
      throwsA(_manifestError(PluginManifestErrorCode.invalidSchema)),
    );
  });

  test('configuration values must survive normalized JSON persistence', () {
    final invalidValues = <(String, Object?)>[
      ('number', double.nan),
      ('number', double.infinity),
      ('array', [DateTime.utc(2026)]),
    ];

    for (final (type, value) in invalidValues) {
      final manifest = PluginManifestV2(
        id: 'fixture',
        name: 'Fixture',
        version: '1.0.0',
        type: PluginType.service,
        contributes: PluginContributions(
          configuration: [
            PluginConfigurationContribution(
              id: 'fixture.value',
              title: 'Value',
              type: type,
              defaultValue: value,
            ),
          ],
        ),
      );

      expect(
        () => PluginManifestValidator().validate(manifest),
        throwsA(_manifestError(PluginManifestErrorCode.invalidSchema)),
        reason: '$type: $value',
      );
    }
  });

  test('array configuration enums use structural JSON equality', () {
    const valid = PluginManifestV2(
      id: 'fixture',
      name: 'Fixture',
      version: '1.0.0',
      type: PluginType.service,
      contributes: PluginContributions(
        configuration: [
          PluginConfigurationContribution(
            id: 'fixture.items',
            title: 'Items',
            type: 'array',
            defaultValue: ['a'],
            enumValues: [
              ['a'],
              ['b'],
            ],
          ),
        ],
      ),
    );
    PluginManifestValidator().validate(valid);

    const invalid = PluginManifestV2(
      id: 'fixture',
      name: 'Fixture',
      version: '1.0.0',
      type: PluginType.service,
      contributes: PluginContributions(
        configuration: [
          PluginConfigurationContribution(
            id: 'fixture.items',
            title: 'Items',
            type: 'array',
            defaultValue: [true],
            enumValues: [
              [1],
            ],
          ),
        ],
      ),
    );
    expect(
      () => PluginManifestValidator().validate(invalid),
      throwsA(_manifestError(PluginManifestErrorCode.invalidSchema)),
    );
  });

  test('when grammar accepts only documented context expressions', () {
    const valid = [
      'plugin.enabled',
      '!device.connected',
      "runtime.language == 'python'",
      '(workspace.opened || plugin.enabled) && !view.active',
      'runtime.state == -2.5',
      'plugin.enabled == true',
    ];
    for (final expression in valid) {
      PluginManifestValidator().validate(_uiManifest(when: expression));
    }
    PluginManifestValidator().validate(
      _uiManifest(when: '${'!' * 63}plugin.enabled'),
    );

    final invalid = [
      '',
      'unknown.key',
      "runtime.state === 'paused'",
      'runtime.state == null',
      'runtime.state == 2.',
      "runtime.state == 'paused' + plugin.enabled",
      '(plugin.enabled',
      '${'!' * 64}plugin.enabled',
      "runtime.state == '${'x' * 4096}'",
      "runtime.state == '${'\u{1F600}' * 2040}'",
    ];
    for (final expression in invalid) {
      expect(
        () => PluginManifestValidator().validate(_uiManifest(when: expression)),
        throwsA(_manifestError(PluginManifestErrorCode.invalidWhen)),
        reason: expression,
      );
    }
    final tooComplex = '${'!' * 300}plugin.enabled';
    expect(
      () => PluginManifestValidator().validate(_uiManifest(when: tooComplex)),
      throwsA(_manifestError(PluginManifestErrorCode.invalidWhen)),
    );
  });
}
