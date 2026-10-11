import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_profile.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_registry.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/pylsp_basedpyright_lsp_server.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/zuban_lsp_server.dart';

LspServerContext contextFor({
  LspType transport = LspType.stdio,
  String executable = '',
  String args = '',
}) {
  return LspServerContext(
    transport: transport,
    stdioExecutable: executable,
    stdioArgs: args,
    stubsEnabled: false,
    stubsPaths: const [],
    pythonInterpreter: '',
    typeCheckingMode: BasedPyrightTypeCheckingMode.standard,
  );
}

LspServerProfileEntry profileEntry(
  Map<String, dynamic> json, {
  String serverId = 'mylsp',
}) {
  return LspServerProfileEntry.fromJson({
    'plugin_id': 'fixture',
    'server_id': serverId,
    ...json,
  });
}

void main() {
  group('LspServerMatchRules', () {
    test('matches bare and pathed executables with and without .exe', () {
      final rules = LspServerMatchRules(executables: ['mylsp']);
      expect(rules.matches(contextFor(executable: 'mylsp')), isTrue);
      expect(
        rules.matches(contextFor(executable: 'C:/tools/mylsp.exe')),
        isTrue,
      );
      expect(rules.matches(contextFor(executable: 'MYLSP')), isTrue);
      expect(rules.matches(contextFor(executable: 'basedpyright')), isFalse);
    });

    test('matches wrapper arguments such as python -m mylsp', () {
      final rules = LspServerMatchRules(executables: ['mylsp']);
      expect(
        rules.matches(contextFor(executable: 'python', args: '-m mylsp')),
        isTrue,
      );
      expect(
        rules.matches(contextFor(executable: 'uvx', args: 'mylsp')),
        isTrue,
      );
    });

    test('respects transport rules', () {
      final rules = LspServerMatchRules(
        executables: ['mylsp'],
        transports: ['stdio'],
      );
      expect(rules.matches(contextFor(executable: 'mylsp')), isTrue);
      expect(
        rules.matches(
          contextFor(transport: LspType.webSocket, executable: 'mylsp'),
        ),
        isFalse,
      );
    });

    test('a profile without executable rules never claims a launch', () {
      // The data API rejects such profiles; the model still treats an empty
      // rule set as no match so a malformed payload cannot hijack servers.
      expect(
        const LspServerMatchRules().matches(contextFor(executable: 'mylsp')),
        isFalse,
      );
    });
  });

  group('LspServerProfileAdapter', () {
    test('builds a flat configuration for the declared keys', () {
      final adapter = LspServerProfileAdapter(
        profileEntry({
          'label': 'MyLSP',
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': {
            'stubs_paths_key': 'extraPaths',
            'python_executable_key': 'python',
            'type_checking_mode_key': 'typeCheckingMode',
            'type_checking_mode_values': {
              'off': 'off',
              'basic': 'default',
              'standard': 'default',
              'strict': 'strict',
              'all': 'all',
            },
          },
        }),
      );
      final context = LspServerContext(
        transport: LspType.stdio,
        stdioExecutable: 'mylsp',
        stdioArgs: '',
        stubsEnabled: true,
        stubsPaths: const ['/stubs/rp2', '/stubs/shared'],
        pythonInterpreter: '/venv/bin/python',
        typeCheckingMode: BasedPyrightTypeCheckingMode.basic,
      );

      expect(adapter.id, 'mylsp');
      expect(adapter.label, 'MyLSP');
      expect(adapter.buildConfiguration(context), {
        'extraPaths': ['/stubs/rp2', '/stubs/shared'],
        'python': '/venv/bin/python',
        'typeCheckingMode': 'default',
      });
    });

    test('nests options under the declared section', () {
      final adapter = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': {
            'mode': 'sectioned',
            'section': 'mylsp',
            'extra': {'diagnosticMode': 'workspace'},
          },
        }),
      );

      expect(adapter.buildConfiguration(contextFor(executable: 'mylsp')), {
        'mylsp': {'diagnosticMode': 'workspace'},
      });
    });

    test('expands environment templates per launch', () {
      final adapter = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': const {},
          'environment': {
            'MYPYPATH': '{stubsPaths}',
            'WORKSPACE': '{workspacePath}',
            'INTERPRETER': '{pythonInterpreter}',
          },
        }),
      );
      final context = LspServerContext(
        transport: LspType.stdio,
        stdioExecutable: 'mylsp',
        stdioArgs: '',
        stubsEnabled: true,
        stubsPaths: const ['/stubs/rp2'],
        pythonInterpreter: '/venv/bin/python',
        typeCheckingMode: BasedPyrightTypeCheckingMode.standard,
        workspacePath: '/workspace',
      );

      expect(adapter.buildEnvironment(context, const {}), {
        'MYPYPATH': '/stubs/rp2',
        'WORKSPACE': '/workspace',
        'INTERPRETER': '/venv/bin/python',
      });
    });

    test('keeps unknown placeholders visible in the value', () {
      final adapter = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': const {},
          'environment': {'FLAG': '{stubsPaths}/{unknown}'},
        }),
      );

      expect(
        adapter.buildEnvironment(
          contextFor(executable: 'mylsp'),
          const {},
        )['FLAG'],
        '/{unknown}',
      );
    });

    test('falls back to the server id when no label is declared', () {
      final adapter = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': const {},
        }),
      );

      expect(adapter.label, 'mylsp');
    });
  });

  group('LspServerRegistry', () {
    test('prefers a contributed profile over the built-in servers', () {
      final profile = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['zuban'],
          },
          'configuration': const {},
        }),
      );
      final registry = LspServerRegistry(contributed: [profile]);

      expect(registry.resolve(contextFor(executable: 'zuban')), same(profile));
    });

    test('resolves the built-in Zuban adapter for zuban launches', () {
      const registry = LspServerRegistry();

      expect(
        registry.resolve(contextFor(executable: 'python', args: '-m zuban')),
        isA<ZubanLspServerAdapter>(),
      );
    });

    test('resolves the fallback adapter for anything else', () {
      const registry = LspServerRegistry();

      expect(
        registry.resolve(contextFor(executable: 'basedpyright')),
        isA<PylspBasedPyrightLspServerAdapter>(),
      );
      expect(
        registry.resolve(contextFor(transport: LspType.webSocket)),
        isA<PylspBasedPyrightLspServerAdapter>(),
      );
    });

    test('resolves conflicting contributed profiles deterministically', () {
      final later = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': const {},
        }, serverId: 'zzz-lsp'),
      );
      final earlier = LspServerProfileAdapter(
        profileEntry({
          'match': {
            'executables': ['mylsp'],
          },
          'configuration': const {},
        }, serverId: 'aaa-lsp'),
      );
      final registry = LspServerRegistry(contributed: [later, earlier]);

      expect(registry.resolve(contextFor(executable: 'mylsp')), same(earlier));
    });
  });

  test('profile entries round-trip through JSON', () {
    final entry = LspServerProfileEntry(
      pluginId: 'fixture',
      serverId: 'mylsp',
      label: 'MyLSP',
      match: const LspServerMatchRules(
        executables: ['mylsp', 'mylsp.exe'],
        transports: ['stdio'],
      ),
      configuration: const LspServerConfigurationSpec(
        mode: LspServerConfigurationSpec.sectionedMode,
        section: 'mylsp',
        stubsPathsKey: 'extraPaths',
        pythonExecutableKey: 'python',
        typeCheckingModeKey: 'typeCheckingMode',
        typeCheckingModeValues: {'off': 'off'},
        extra: {'diagnosticMode': 'workspace'},
      ),
      environment: const {'MYPYPATH': '{stubsPaths}'},
    );

    final restored = LspServerProfileEntry.fromJson(entry.toJson());

    expect(restored.pluginId, entry.pluginId);
    expect(restored.serverId, entry.serverId);
    expect(restored.label, entry.label);
    expect(restored.match.executables, entry.match.executables);
    expect(restored.match.transports, entry.match.transports);
    expect(restored.configuration.section, 'mylsp');
    expect(restored.configuration.stubsPathsKey, 'extraPaths');
    expect(restored.configuration.pythonExecutableKey, 'python');
    expect(restored.configuration.typeCheckingModeKey, 'typeCheckingMode');
    expect(restored.configuration.typeCheckingModeValues, {'off': 'off'});
    expect(restored.configuration.extra, {'diagnosticMode': 'workspace'});
    expect(restored.environment, entry.environment);
  });
}
