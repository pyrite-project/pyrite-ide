enum LspType {
  webSocket,
  stdio;

  /// Python-friendly snake_case name for settings API.
  String get jsonName => switch (this) {
    LspType.webSocket => 'web_socket',
    LspType.stdio => 'stdio',
  };

  static LspType? fromJsonName(String? value) => switch (value) {
    'web_socket' => LspType.webSocket,
    'stdio' => LspType.stdio,
    _ => null,
  };
}

/// How strictly the language server should type-check the workspace.
///
/// The levels are the vocabulary the IDE exposes to language-server plugins:
/// a contributed profile maps them onto whatever its own server understands
/// (`type_checking_mode_values`), so no single server's option set is baked
/// into the settings page. Servers without a strictness ladder ignore it.
enum LspTypeCheckingMode {
  off,
  basic,
  standard,
  strict,
  all;

  String get jsonName => name;

  static LspTypeCheckingMode? fromJsonName(String? value) {
    return switch (value) {
      'off' => LspTypeCheckingMode.off,
      'basic' => LspTypeCheckingMode.basic,
      'standard' => LspTypeCheckingMode.standard,
      'strict' => LspTypeCheckingMode.strict,
      'all' => LspTypeCheckingMode.all,
      _ => null,
    };
  }
}

/// How sibling entries in a file tree are ordered.
///
/// [byName] sorts everything by name with folders interleaved among the
/// files, like the raw directory listing a file manager shows in name order.
/// [byType] groups by kind -- folders first, then files by extension. The two
/// modes must stay visibly different: with folders forced to the top in both,
/// neither order would look like what its label promises.
enum FileSortMode {
  /// Alphabetical by name, case-insensitively, folders interleaved.
  byName,

  /// Folders first, then files grouped by extension, alphabetical within
  /// each group.
  byType;

  String get jsonName => switch (this) {
    FileSortMode.byName => 'name',
    FileSortMode.byType => 'type',
  };

  static FileSortMode fromJsonName(String? value) => switch (value) {
    'type' => FileSortMode.byType,
    _ => FileSortMode.byName,
  };
}

class MicroPythonStubsLayer {
  const MicroPythonStubsLayer({required this.provider, required this.profile});

  final String provider;
  final String profile;

  Map<String, dynamic> toJson() => {'provider': provider, 'profile': profile};

  factory MicroPythonStubsLayer.fromJson(Map<String, dynamic> json) {
    return MicroPythonStubsLayer(
      provider: json['provider']?.toString() ?? '',
      profile: json['profile']?.toString() ?? '',
    );
  }
}
