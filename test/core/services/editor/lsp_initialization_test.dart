import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LSP initialization sends one request before initialized', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var initializeRequests = 0;
    final initialized = Completer<void>();
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((message) {
        final request = jsonDecode(message as String) as Map<String, dynamic>;
        switch (request['method']) {
          case 'initialize':
            initializeRequests++;
            socket.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': request['id'],
                'result': {'capabilities': {}},
              }),
            );
          case 'initialized':
            if (!initialized.isCompleted) initialized.complete();
        }
      });
    });

    final config = LspSocketConfig(
      workspacePath: Directory.current.path,
      languageId: 'test',
      serverUrl: 'ws://${server.address.address}:${server.port}',
    );
    addTearDown(config.dispose);
    await config.connect();

    await Future.wait([config.initialize(), config.initialize()]);
    await initialized.future.timeout(const Duration(seconds: 1));

    expect(initializeRequests, 1);
  });
}
