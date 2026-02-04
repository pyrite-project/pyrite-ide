import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/app.dart';

var example = {
  "jsonrpc": "2.0",
  "method": "textDocument\/publishDiagnostics",
  "params": {
    "uri":
        "file:\/\/\/C:\/Users\/can1425\/handpyre-firm\/port\/boards\/pins_prefix.c",
    "diagnostics": [
      {
        "source": "pycodestyle",
        "range": {
          "start": {"line": 0, "character": 0},
          "end": {"line": 0, "character": 20},
        },
        "message": "E265 block comment should start with '# '",
        "code": "E265",
        "severity": 2,
      },
      {
        "source": "pycodestyle",
        "range": {
          "start": {"line": 1, "character": 0},
          "end": {"line": 1, "character": 31},
        },
        "message": "E265 block comment should start with '# '",
        "code": "E265",
        "severity": 2,
      },
      {
        "source": "pycodestyle",
        "range": {
          "start": {"line": 2, "character": 0},
          "end": {"line": 2, "character": 25},
        },
        "message": "E265 block comment should start with '# '",
        "code": "E265",
        "severity": 2,
      },
      {
        "source": "pycodestyle",
        "range": {
          "start": {"line": 3, "character": 0},
          "end": {"line": 3, "character": 25},
        },
        "message": "E265 block comment should start with '# '",
        "code": "E265",
        "severity": 2,
      },
    ],
    "version": 1,
  },
};

final StateProvider<String?> activeDiagnosticUri = StateProvider<String?>(
  (ref) => null,
);

final StateProvider<Map<String, List<DiagnosticItem>>> diagnosticsByUri =
    StateProvider<Map<String, List<DiagnosticItem>>>((ref) => {});

final Provider<List<DiagnosticItem>> diagnostics = Provider<List<DiagnosticItem>>(
  (ref) {
    final uri = ref.watch(activeDiagnosticUri);
    if (uri == null) return const [];

    final byUri = ref.watch(diagnosticsByUri);
    return byUri[uri] ?? const [];
  },
);

void handleDiagnostics(Map<String, dynamic> params) {
  final String uri = params["uri"];
  final List<dynamic> rawDiagnostics = params["diagnostics"] ?? const [];
  final items = rawDiagnostics
      .whereType<Map<String, dynamic>>()
      .map((e) => DiagnosticItem.fromJson(e))
      .toList(growable: false);

  container.read(diagnosticsByUri.notifier).state = {
    ...container.read(diagnosticsByUri),
    uri: items,
  };
}

void cleanDiagnostics(dynamic ref) {
  container.read(activeDiagnosticUri.notifier).state = null;
}

class DiagnosticItem {
  const DiagnosticItem({
    required this.source,
    required this.range,
    required this.message,
    required this.code,
    required this.severity,
  });

  final String source;
  final Range range;
  final String message;
  final String? code;
  final int severity;

  factory DiagnosticItem.fromJson(Map<String, dynamic> json) {
    return DiagnosticItem(
      source: json["source"],
      range: Range.fromJson(json["range"]),
      message: json["message"],
      code: json["code"],
      severity: json["severity"],
    );
  }
}

class Range {
  const Range({required this.start, required this.end});

  final Map<String, dynamic> start;
  final Map<String, dynamic> end;

  factory Range.fromJson(Map<String, dynamic> json) {
    return Range(
      start: (json["start"]! as Map<String, dynamic>),
      end: json["end"]! as Map<String, dynamic>,
    );
  }
}
