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
