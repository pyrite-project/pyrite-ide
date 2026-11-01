import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_adapter.dart';
import 'package:pyrite_ide/core/services/editor/lsp_server/lsp_server_context.dart';

/// Copies a decoded JSON object into a `String → String` map, stringifying
/// every key and value; non-map input yields an empty map.
Map<String, String> stringMap(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          entry.key.toString(): entry.value.toString(),
      }
    : const <String, String>{};

/// Recognizes one language server launch by matching its stdio command tokens.
///
/// [executables] are matched against the basename of every token — bare names
/// and trailing paths both work, and a Windows `.exe` suffix is ignored — so a
/// rule of `zuban` matches `zuban`, `C:/tools/zuban.exe`, and the `zuban`
/// argument of `python -m zuban`. [transports] optionally narrows the match to
/// [LspType.jsonName] values; an empty list accepts any transport.
class LspServerMatchRules {
  const LspServerMatchRules({
    this.executables = const [],
    this.transports = const [],
  });

  final List<String> executables;
  final List<String> transports;

  bool matches(LspServerContext context) {
    if (transports.isNotEmpty &&
        !transports.contains(context.transport.jsonName)) {
      return false;
    }
    // Executable-less rules match every launch of the listed transports; with
    // no rules at all, nothing matches.
    if (executables.isEmpty) return transports.isNotEmpty;
    final tokens = context.stdioCommandTokens
        .map(normalizeCommandToken)
        .toSet();
    return executables.any(
      (rule) => tokens.contains(normalizeCommandToken(rule)),
    );
  }

  /// Lower-cased basename without a Windows `.exe` suffix, so rules and
  /// command tokens compare equal across spellings.
  static String normalizeCommandToken(String token) {
    var base = path.basename(token.trim().toLowerCase());
    if (base.endsWith('.exe')) base = base.substring(0, base.length - 4);
    return base;
  }

  Map<String, dynamic> toJson() => {
    'executables': executables,
    'transports': transports,
  };

  factory LspServerMatchRules.fromJson(Map<String, dynamic> json) {
    return LspServerMatchRules(
      executables: (json['executables'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      transports: (json['transports'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

/// Declarative description of the configuration a contributed server expects.
///
/// [mode] selects between a flat options object (`flat`, e.g. Zuban) and one
/// nested under [section] (`sectioned`, e.g. `{'mylsp': {...}}`). The common
/// inputs are placed under the keys the server reads: [stubsPathsKey] receives
/// the resolved stubs directories, [pythonExecutableKey] the selected
/// interpreter, and [typeCheckingModeKey] the configured strictness level,
/// translated through [typeCheckingModeValues] (a BasedPyright level name to
/// the server's own value; unmapped levels pass through unchanged). [extra]
/// carries static options verbatim.
class LspServerConfigurationSpec {
  const LspServerConfigurationSpec({
    this.mode = 'flat',
    this.section,
    this.stubsPathsKey,
    this.pythonExecutableKey,
    this.typeCheckingModeKey,
    this.typeCheckingModeValues = const {},
    this.extra = const {},
  });

  static const String flatMode = 'flat';
  static const String sectionedMode = 'sectioned';

  final String mode;
  final String? section;
  final String? stubsPathsKey;
  final String? pythonExecutableKey;
  final String? typeCheckingModeKey;
  final Map<String, String> typeCheckingModeValues;
  final Map<String, dynamic> extra;

  Map<String, dynamic> build(LspServerContext context) {
    final options = <String, dynamic>{
      if (stubsPathsKey != null && context.stubsPaths.isNotEmpty)
        stubsPathsKey!: context.stubsPaths,
      if (pythonExecutableKey != null && context.pythonInterpreter.isNotEmpty)
        pythonExecutableKey!: context.pythonInterpreter,
      ?typeCheckingModeKey: mapTypeCheckingMode(context.typeCheckingMode),
      ...extra,
    };
    if (mode != sectionedMode) return options;
    final section = this.section;
    if (section == null || section.isEmpty) return options;
    return {section: options};
  }

  String mapTypeCheckingMode(BasedPyrightTypeCheckingMode mode) =>
      typeCheckingModeValues[mode.jsonName] ?? mode.jsonName;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    if (section != null) 'section': section,
    if (stubsPathsKey != null) 'stubs_paths_key': stubsPathsKey,
    if (pythonExecutableKey != null)
      'python_executable_key': pythonExecutableKey,
    if (typeCheckingModeKey != null)
      'type_checking_mode_key': typeCheckingModeKey,
    if (typeCheckingModeValues.isNotEmpty)
      'type_checking_mode_values': typeCheckingModeValues,
    'extra': extra,
  };

  factory LspServerConfigurationSpec.fromJson(Map<String, dynamic> json) {
    return LspServerConfigurationSpec(
      mode: json['mode']?.toString() == sectionedMode
          ? sectionedMode
          : flatMode,
      section: json['section']?.toString(),
      stubsPathsKey: json['stubs_paths_key']?.toString(),
      pythonExecutableKey: json['python_executable_key']?.toString(),
      typeCheckingModeKey: json['type_checking_mode_key']?.toString(),
      typeCheckingModeValues: stringMap(json['type_checking_mode_values']),
      extra: Map<String, dynamic>.from(json['extra'] as Map? ?? {}),
    );
  }
}

/// One language-server support profile contributed by a data plugin.
///
/// Unlike the built-in adapters this carries no code: matching rules, option
/// keys, static extras, and environment templates fully describe the server,
/// which keeps third-party contributions serializable and sandboxed.
class LspServerProfileEntry {
  const LspServerProfileEntry({
    required this.pluginId,
    required this.serverId,
    required this.match,
    required this.configuration,
    this.label = '',
    this.environment = const {},
  });

  final String pluginId;
  final String serverId;
  final String label;
  final LspServerMatchRules match;
  final LspServerConfigurationSpec configuration;

  /// Environment templates with `{stubsPaths}`, `{pythonInterpreter}`, and
  /// `{workspacePath}` placeholders expanded per launch.
  final Map<String, String> environment;

  Map<String, dynamic> toJson() => {
    'plugin_id': pluginId,
    'server_id': serverId,
    'label': label,
    'match': match.toJson(),
    'configuration': configuration.toJson(),
    'environment': environment,
  };

  factory LspServerProfileEntry.fromJson(Map<String, dynamic> json) {
    return LspServerProfileEntry(
      pluginId: json['plugin_id']?.toString() ?? '',
      serverId: json['server_id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      match: LspServerMatchRules.fromJson(
        Map<String, dynamic>.from(json['match'] as Map? ?? {}),
      ),
      configuration: LspServerConfigurationSpec.fromJson(
        Map<String, dynamic>.from(json['configuration'] as Map? ?? {}),
      ),
      environment: stringMap(json['environment']),
    );
  }
}

/// Serves launches recognized by a plugin-contributed [LspServerProfileEntry].
class LspServerProfileAdapter extends LspServerAdapter {
  const LspServerProfileAdapter(this.entry);

  final LspServerProfileEntry entry;

  @override
  String get id => entry.serverId;

  @override
  String get label => entry.label.isEmpty ? entry.serverId : entry.label;

  @override
  bool matches(LspServerContext context) => entry.match.matches(context);

  @override
  Map<String, dynamic> buildConfiguration(LspServerContext context) =>
      entry.configuration.build(context);

  @override
  Map<String, String> buildEnvironment(
    LspServerContext context,
    Map<String, String> baseEnvironment,
  ) => {
    for (final template in entry.environment.entries)
      template.key: expandTemplate(template.value, context),
  };

  /// Fills the supported placeholders; unknown ones stay verbatim so a typo
  /// is visible in the launched process instead of silently vanishing.
  static String expandTemplate(String template, LspServerContext context) =>
      template
          .replaceAll(
            '{stubsPaths}',
            context.stubsPaths.join(Platform.isWindows ? ';' : ':'),
          )
          .replaceAll('{pythonInterpreter}', context.pythonInterpreter)
          .replaceAll('{workspacePath}', context.workspacePath);
}
