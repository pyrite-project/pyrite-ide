import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configuration = <String, dynamic>{
    'python': {'venvPath': '/workspace', 'venv': '.venv'},
    'basedpyright': {
      'analysis': {
        'extraPaths': ['/workspace/stubs'],
      },
    },
  };

  test(
    'returns the requested basedpyright workspace configuration section',
    () {
      expect(
        LspConfig.workspaceConfigurationForSection(
          configuration,
          'basedpyright.analysis',
        ),
        {
          'extraPaths': ['/workspace/stubs'],
        },
      );
    },
  );

  test('returns virtual environment configuration for Pyright', () {
    expect(
      LspConfig.workspaceConfigurationForSection(configuration, 'python'),
      {'venvPath': '/workspace', 'venv': '.venv'},
    );
    expect(
      LspConfig.workspaceConfigurationForSection(configuration, 'python.venv'),
      '.venv',
    );
  });

  test('returns null for an unknown workspace configuration section', () {
    expect(
      LspConfig.workspaceConfigurationForSection(configuration, 'pylsp'),
      isNull,
    );
  });
}
