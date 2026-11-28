import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_profile.dart';

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
    typeCheckingMode: LspTypeCheckingMode.standard,
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

  group('LspServerProfileEntry', () {
    test('builds a flat configuration for the declared keys', () {
      final profile = profileEntry({
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
      });
      final context = LspServerContext(
        transport: LspType.stdio,
        stdioExecutable: 'mylsp',
        stdioArgs: '',
        stubsEnabled: true,
        stubsPaths: const ['/stubs/rp2', '/stubs/shared'],
        pythonInterpreter: '/venv/bin/python',
        typeCheckingMode: LspTypeCheckingMode.basic,
      );

      expect(profile.label, 'MyLSP');
      expect(profile.buildConfiguration(context), {
        'extraPaths': ['/stubs/rp2', '/stubs/shared'],
        'python': '/venv/bin/python',
        'typeCheckingMode': 'default',
      });
    });

    test('nests options under the declared section', () {
      final profile = profileEntry({
        'match': {
          'executables': ['mylsp'],
        },
        'configuration': {
          'mode': 'sectioned',
          'section': 'mylsp',
          'extra': {'diagnosticMode': 'workspace'},
        },
      });

      expect(profile.buildConfiguration(contextFor(executable: 'mylsp')), {
        'mylsp': {'diagnosticMode': 'workspace'},
      });
    });

    test('treats dots in option keys as nesting', () {
      // pylsp reads its jedi settings two levels down; a profile has to be able
      // to address that path without IDE-side code for its option shape.
      final profile = profileEntry({
        'match': {
          'executables': ['pylsp'],
        },
        'configuration': {
          'mode': 'sectioned',
          'section': 'pylsp',
          'stubs_paths_key': 'plugins.jedi.extra_paths',
          'python_executable_key': 'plugins.jedi.environment',
          'extra': {'plugins.jedi.prioritize_extra_paths': true},
        },
      });
      final context = LspServerContext(
        transport: LspType.stdio,
        stdioExecutable: 'python',
        stdioArgs: '-m pylsp',
        stubsEnabled: true,
        stubsPaths: const ['/stubs/rp2'],
        pythonInterpreter: '/venv/bin/python',
        typeCheckingMode: LspTypeCheckingMode.standard,
      );

      expect(profile.buildConfiguration(context), {
        'pylsp': {
          'plugins': {
            'jedi': {
              'extra_paths': ['/stubs/rp2'],
              'environment': '/venv/bin/python',
              'prioritize_extra_paths': true,
            },
          },
        },
      });
    });

    test('expands environment templates per launch', () {
      final profile = profileEntry({
        'match': {
          'executables': ['mylsp'],
        },
        'configuration': const {},
        'environment': {
          'MYPYPATH': '{stubsPaths}',
          'WORKSPACE': '{workspacePath}',
          'INTERPRETER': '{pythonInterpreter}',
        },
      });
      final context = LspServerContext(
        transport: LspType.stdio,
        stdioExecutable: 'mylsp',
        stdioArgs: '',
        stubsEnabled: true,
        stubsPaths: const ['/stubs/rp2'],
        pythonInterpreter: '/venv/bin/python',
        typeCheckingMode: LspTypeCheckingMode.standard,
        workspacePath: '/workspace',
      );

      expect(profile.buildEnvironment(context), {
        'MYPYPATH': '/stubs/rp2',
        'WORKSPACE': '/workspace',
        'INTERPRETER': '/venv/bin/python',
      });
    });

    test('keeps unknown placeholders visible in the value', () {
      final profile = profileEntry({
        'match': {
          'executables': ['mylsp'],
        },
        'configuration': const {},
        'environment': {'FLAG': '{stubsPaths}/{unknown}'},
      });

      expect(
        profile.buildEnvironment(contextFor(executable: 'mylsp'))['FLAG'],
        '/{unknown}',
      );
    });
  });

  group('resolveLspServerProfile', () {
    test('resolves the profile that claims the launch', () {
      final profile = profileEntry({
        'match': {
          'executables': ['zuban'],
        },
        'configuration': const {},
      });

      expect(
        resolveLspServerProfile([profile], contextFor(executable: 'zuban')),
        same(profile),
      );
    });

    test('resolves no profile for a launch nothing describes', () {
      // The IDE carries no server's option shape itself: an unclaimed launch
      // gets no configuration instead of another server's payload.
      final profile = profileEntry({
        'match': {
          'executables': ['zuban'],
        },
        'configuration': const {},
      });

      expect(
        resolveLspServerProfile([profile], contextFor(executable: 'pylsp')),
        isNull,
      );
      expect(
        resolveLspServerProfile([
          profile,
        ], contextFor(transport: LspType.webSocket)),
        isNull,
      );
      expect(
        resolveLspServerProfile(const [], contextFor(executable: 'pylsp')),
        isNull,
      );
    });

    test('resolves conflicting contributed profiles deterministically', () {
      final later = profileEntry({
        'match': {
          'executables': ['mylsp'],
        },
        'configuration': const {},
      }, serverId: 'zzz-lsp');
      final earlier = profileEntry({
        'match': {
          'executables': ['mylsp'],
        },
        'configuration': const {},
      }, serverId: 'aaa-lsp');

      expect(
        resolveLspServerProfile([
          later,
          earlier,
        ], contextFor(executable: 'mylsp')),
        same(earlier),
      );
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
