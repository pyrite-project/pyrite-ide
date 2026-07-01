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

class MicroPythonStubsLayer {
  const MicroPythonStubsLayer({
    required this.provider,
    required this.profile,
  });

  final String provider;
  final String profile;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'profile': profile,
  };

  factory MicroPythonStubsLayer.fromJson(Map<String, dynamic> json) {
    return MicroPythonStubsLayer(
      provider: json['provider']?.toString() ?? '',
      profile: json['profile']?.toString() ?? '',
    );
  }
}
