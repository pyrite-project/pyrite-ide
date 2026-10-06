import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

/// A language server stub that answers whatever it is asked and records the
/// requests it saw, so a test can tell "the client did not ask" from "the
/// server answered nothing".
class _FakeServer {
  _FakeServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> requests = [];
  final Completer<void> connected = Completer<void>();

  Map<String, dynamic>? initializeParams;

  static Future<_FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeServer._(server);
    server.transform(WebSocketTransformer()).listen((socket) {
      if (!fake.connected.isCompleted) fake.connected.complete();
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        fake.requests.add(request);
        if (request['method'] == 'initialize') {
          fake.initializeParams =
              request['params'] as Map<String, dynamic>;
        }
        if (request['id'] != null) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': fake._resultFor(request['method'] as String?),
            }),
          );
        }
      });
    });
    return fake;
  }

  dynamic _resultFor(String? method) => switch (method) {
    'textDocument/definition' => [
      {
        'uri': 'file:///probe.py',
        'range': {
          'start': {'line': 1, 'character': 0},
          'end': {'line': 1, 'character': 3},
        },
      },
    ],
    'textDocument/foldingRange' => <dynamic>[],
    _ => <String, dynamic>{},
  };

  String get url => 'ws://${_server.address.address}:${_server.port}';

  Iterable<String> get methods => requests.map((r) => r['method'] as String);

  Future<void> dispose() => _server.close(force: true);
}

void main() {
  group('LspClientCapabilities.applyFrom', () {
    test('overwrites every flag on the same instance', () {
      final live = LspClientCapabilities();
      final next = LspClientCapabilities.disableAll;

      live.applyFrom(next);

      expect(live.semanticHighlighting, isFalse);
      expect(live.codeCompletion, isFalse);
      expect(live.hoverInfo, isFalse);
      expect(live.codeAction, isFalse);
      expect(live.signatureHelp, isFalse);
      expect(live.documentColor, isFalse);
      expect(live.documentHighlight, isFalse);
      expect(live.codeFolding, isFalse);
      expect(live.inlayHint, isFalse);
      expect(live.goToDefinition, isFalse);
      expect(live.rename, isFalse);
    });
  });

  group('initialize capabilities', () {
    test('advertises definition, rename and code action', () async {
      final server = await _FakeServer.start();
      addTearDown(server.dispose);

      final config = LspSocketConfig(
        workspacePath: Directory.current.path,
        languageId: 'test',
        serverUrl: server.url,
        capabilities: LspClientCapabilities(),
      );
      addTearDown(config.dispose);
      await config.connect();
      await config.initialize();

      final textDocument =
          (server.initializeParams!['capabilities'] as Map<String, dynamic>)[
              'textDocument'] as Map<String, dynamic>;
      expect(textDocument['definition'], isNotNull);
      expect(textDocument['rename'], isNotNull);
      expect(textDocument['codeAction'], isNotNull);
    });

    test('omits definition, rename and code action when disabled', () async {
      final server = await _FakeServer.start();
      addTearDown(server.dispose);

      final config = LspSocketConfig(
        workspacePath: Directory.current.path,
        languageId: 'test',
        serverUrl: server.url,
        capabilities: LspClientCapabilities(
          goToDefinition: false,
          rename: false,
          codeAction: false,
        ),
      );
      addTearDown(config.dispose);
      await config.connect();
      await config.initialize();

      final textDocument =
          (server.initializeParams!['capabilities'] as Map<String, dynamic>)[
              'textDocument'] as Map<String, dynamic>;
      expect(textDocument.containsKey('definition'), isFalse);
      expect(textDocument.containsKey('rename'), isFalse);
      expect(textDocument.containsKey('codeAction'), isFalse);
    });
  });

  group('flipping a capability on a running server', () {
    test('stops and restarts the gated request', () async {
      final server = await _FakeServer.start();
      addTearDown(server.dispose);

      final config = LspSocketConfig(
        workspacePath: Directory.current.path,
        languageId: 'test',
        serverUrl: server.url,
        capabilities: LspClientCapabilities(codeFolding: true),
      );
      addTearDown(config.dispose);
      await config.connect();
      await config.initialize();

      final file = File('${Directory.current.path}/capability_probe.py');

      await config.getLSPFoldRanges(file.path);
      expect(server.methods, contains('textDocument/foldingRange'));

      config.capabilities.applyFrom(LspClientCapabilities(codeFolding: false));
      await config.getLSPFoldRanges(file.path);
      expect(
        server.methods.where((m) => m == 'textDocument/foldingRange'),
        hasLength(1),
        reason: 'a disabled capability must not put a request on the wire',
      );

      config.capabilities.applyFrom(LspClientCapabilities(codeFolding: true));
      await config.getLSPFoldRanges(file.path);
      expect(
        server.methods.where((m) => m == 'textDocument/foldingRange'),
        hasLength(2),
      );
    });

    test('stops go-to-definition without touching the server', () async {
      final server = await _FakeServer.start();
      addTearDown(server.dispose);

      final config = LspSocketConfig(
        workspacePath: Directory.current.path,
        languageId: 'test',
        serverUrl: server.url,
        capabilities: LspClientCapabilities(goToDefinition: true),
      );
      addTearDown(config.dispose);
      await config.connect();
      await config.initialize();

      final file = File('${Directory.current.path}/capability_probe.py');
      await config.getDefinition(file.path, 0, 0);
      expect(server.methods, contains('textDocument/definition'));

      config.capabilities.applyFrom(
        LspClientCapabilities(goToDefinition: false),
      );
      expect(await config.getDefinition(file.path, 0, 0), isEmpty);
      expect(
        server.methods.where((m) => m == 'textDocument/definition'),
        hasLength(1),
      );
    });
  });
}