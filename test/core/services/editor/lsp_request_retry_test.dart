import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'LSP syncs documents and retries JSON-RPC errors up to three times',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var retryCount = 0;
      var didOpenReceived = false;
      server.transform(WebSocketTransformer()).listen((socket) {
        socket.listen((message) {
          final request = jsonDecode(message as String) as Map<String, dynamic>;
          if (request['method'] == 'textDocument/didOpen') {
            didOpenReceived = true;
            return;
          }
          if (request['method'] == 'initialized') return;
          if (request['method'] == 'initialize') {
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': request['id'],
                'result': {'capabilities': {}},
              }),
            );
            return;
          }
          retryCount++;
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              if (retryCount <= 3)
                'error': {'code': -32000, 'message': 'temporary'}
              else
                'result': 'ok',
            }),
          );
        });
      });

      final config = LspSocketConfig(
        workspacePath: Directory.current.path,
        languageId: 'test',
        serverUrl: 'ws://${server.address.address}:${server.port}',
      );
      addTearDown(config.dispose);
      await config.connect();
      await config.initialize();
      await config.syncDocument('/tmp/lsp_retry_test.py', 'c = 5');

      final response = await config.sendRequest(
        method: 'test/retry',
        params: {},
      );

      expect(didOpenReceived, isTrue);
      expect(response['result'], 'ok');
      expect(retryCount, 4);
    },
  );

  test('requests before the initialize handshake are rejected locally',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String>[];
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        received.add(request['method'] as String);
      });
    });

    final config = LspSocketConfig(
      workspacePath: Directory.current.path,
      languageId: 'test',
      serverUrl: 'ws://${server.address.address}:${server.port}',
    );
    addTearDown(config.dispose);
    await config.connect();

    // A request racing the startup must stay a local error: servers such as
    // zuban exit on any request that arrives before `initialized`.
    await expectLater(
      config.getDocumentColor('/tmp/lsp_early_request_test.py'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('textDocument/documentColor'),
        ),
      ),
    );
    expect(received, isEmpty);
  });

  test('initialize is answered once and never resent on an error response',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var initializeCount = 0;
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        if (request['method'] != 'initialize') return;
        initializeCount++;
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            'error': {'code': -32000, 'message': 'temporary'},
          }),
        );
      });
    });

    final config = LspSocketConfig(
      workspacePath: Directory.current.path,
      languageId: 'test',
      serverUrl: 'ws://${server.address.address}:${server.port}',
    );
    addTearDown(config.dispose);
    await config.connect();

    final response = await config.sendRequest(
      method: 'initialize',
      params: {},
    );

    // Resending `initialize` is a protocol violation that strict servers
    // (zuban) answer by exiting, so the error response is returned as-is.
    expect(initializeCount, 1);
    expect(response['error'], isNotNull);
  });
}
