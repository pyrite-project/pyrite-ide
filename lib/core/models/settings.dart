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

enum BasedPyrightTypeCheckingMode {
  off,
  basic,
  standard,
  strict,
  all;

  String get jsonName => name;

  static BasedPyrightTypeCheckingMode? fromJsonName(String? value) {
    return switch (value) {
      'off' => BasedPyrightTypeCheckingMode.off,
      'basic' => BasedPyrightTypeCheckingMode.basic,
      'standard' => BasedPyrightTypeCheckingMode.standard,
      'strict' => BasedPyrightTypeCheckingMode.strict,
      'all' => BasedPyrightTypeCheckingMode.all,
      _ => null,
    };
  }
}

/// How sibling entries in a file tree are ordered.
///
/// Folders always come first -- both trees are explorers, and mixing a folder
/// into a run of files makes the list harder to scan than it makes the names
/// alphabetical. The mode only decides how the files below them are ordered.
enum FileSortMode {
  /// Alphabetical by name, case-insensitively.
  byName,

  /// Grouped by extension, then alphabetical within each group.
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
