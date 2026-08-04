import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/permission_log.dart';
import 'package:pyrite_ide/core/sdk/permissions.dart';
import 'package:pyrite_ide/core/sdk/plugin_run_manager.dart';

void main() {
  test('every public SDK API command has an explicit permission policy', () {
    final commandPattern = RegExp(
      r"static const String\s+\w+\s*=\s*'([^']+)'",
      multiLine: true,
    );
    final commands = <String>{
      SdkCommands.outputAppend,
      SdkCommands.pathRequest,
    };
    for (final entity in Directory('lib/core/sdk/api').listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      commands.addAll(
        commandPattern
            .allMatches(source)
            .map((match) => match.group(1)!)
            .where((command) => command.startsWith('sdk.')),
      );
    }

    final missing = commands.where((command) => !Permissions.isKnown(command));

    expect(missing, isEmpty, reason: 'Commands without a permission policy');
    expect(
      Permissions.publicCommands.intersection(
        Permissions.commandRequirements.keys.toSet(),
      ),
      isEmpty,
    );
    for (final requirement in Permissions.commandRequirements.values) {
      expect(
        requirement,
        matches(RegExp(r'^[a-z][a-z0-9_.]*:[a-z][a-z0-9_.]*$')),
      );
    }
  });

  test('permission log preserves allowed denied and unknown decisions', () {
    for (final decision in PermissionDecision.values) {
      final original = PermissionLogEntry(
        pluginId: 'fixture',
        command: 'sdk.fixture.command',
        required: 'fixture:read',
        decision: decision,
        timestamp: 1,
      );

      final decoded = PermissionLogEntry.fromJson(original.toJson());

      expect(decoded.decision, decision);
      expect(decoded.granted, decision == PermissionDecision.allowed);
    }
  });
}
