import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/lsp_workspace_path.dart';

void main() {
  test('uses the opened project as the LSP workspace for a contained file', () {
    final root = Directory.systemTemp.createTempSync('pyrite-workspace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final sourceDirectory = Directory(
      '${root.path}${Platform.pathSeparator}examples${Platform.pathSeparator}plugin',
    )..createSync(recursive: true);
    final file = File('${sourceDirectory.path}${Platform.pathSeparator}main.py')
      ..createSync();

    expect(lspWorkspacePathForFile(file, root), root.path);
  });

  test('uses the parent directory for a file outside the opened project', () {
    final root = Directory.systemTemp.createTempSync('pyrite-workspace-');
    final otherRoot = Directory.systemTemp.createTempSync('pyrite-other-');
    addTearDown(() => root.deleteSync(recursive: true));
    addTearDown(() => otherRoot.deleteSync(recursive: true));
    final file = File('${otherRoot.path}${Platform.pathSeparator}main.py')
      ..createSync();

    expect(lspWorkspacePathForFile(file, root), otherRoot.path);
  });
}
