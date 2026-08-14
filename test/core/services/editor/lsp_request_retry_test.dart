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
      var requestCount = 0;
      var syncReceived = false;
      server.transform(WebSocketTransformer()).listen((socket) {
        socket.listen((message) {
          final request = jsonDecode(message as String) as Map<String, dynamic>;
          if (!request.containsKey('id')) {
            syncReceived = true;
            return;
          }
          requestCount++;
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              if (requestCount <= 3)
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
      await config.syncDocument('/tmp/lsp_retry_test.py', 'c = 5');

      final response = await config.sendRequest(
        method: 'test/retry',
        params: {},
      );

      expect(syncReceived, isTrue);
      expect(response['result'], 'ok');
      expect(requestCount, 4);
    },
  );
}
