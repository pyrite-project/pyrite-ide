import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pyrite_ide/core/sdk/python_bridge_plugin_transport.dart';
import 'package:serious_python/serious_python.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three real PythonBridge channels round-trip byte payloads', (
    tester,
  ) async {
    final transports = List.generate(
      3,
      (index) => PythonBridgePluginTransport(
        channelLabel: 'pyrite.t04.integration.$index',
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    await Future.wait(transports.map((transport) => transport.start()));
    final channels = [
      for (final transport in transports)
        {'port': transport.port, 'label': transport.channelLabel},
    ];

    final scriptPath = await extractAsset(
      'test/fixtures/python_bridge_transport/echo.py',
    );
    final sdkTransportPath = await extractAsset(
      'test/fixtures/python_bridge_transport/pyrite_sdk/core/transport.py',
    );
    await extractAsset(
      'test/fixtures/python_bridge_transport/pyrite_sdk/core/dart_bridge_transport.py',
    );
    final sdkSourcePath = File(sdkTransportPath).parent.parent.parent.path;

    final startupMessage = transports.first.messages.first;
    await SeriousPython.runProgram(
      scriptPath,
      environmentVariables: {
        ...transports.first.startupEnvironment,
        'PYRITE_IDE_TEST_CHANNELS': jsonEncode(channels),
        'PYRITE_IDE_TEST_SDK_SRC': sdkSourcePath,
      },
    );
    final startupText = utf8.decode(
      await startupMessage.timeout(const Duration(seconds: 30)),
    );
    expect(startupText, '__pyrite_transport_ready__');

    final sizes = [0, 1, 1024, 64 * 1024, 1024 * 1024];
    for (
      var channelIndex = 0;
      channelIndex < transports.length;
      channelIndex++
    ) {
      final transport = transports[channelIndex];
      for (final size in sizes) {
        final payload = Uint8List.fromList(
          List<int>.generate(size, (index) => (index + channelIndex) & 0xff),
        );
        final reply = transport.messages.first;
        await transport.send(payload);
        expect(await reply.timeout(const Duration(seconds: 30)), payload);
      }
    }

    for (final transport in transports) {
      await transport.send(
        Uint8List.fromList(utf8.encode('__close_pyrite_transport__')),
      );
      await transport.close();
    }

    await SeriousPython.resetRuntime().timeout(const Duration(seconds: 30));
  });

  testWidgets('persistent run and reset commands retain submission order', (
    tester,
  ) async {
    final completions = <String>[];

    final runA =
        SeriousPython.runProgram(
          'ordering-a.py',
          script: 'import time; time.sleep(0.2)',
          sync: true,
        ).then((error) {
          expect(error, isNull);
          completions.add('A');
        });
    await Future<void>.delayed(Duration.zero);

    final reset1 = SeriousPython.resetRuntime().then((_) {
      completions.add('R1');
    });
    await Future<void>.delayed(Duration.zero);

    final runB =
        SeriousPython.runProgram(
          'ordering-b.py',
          script: 'pass',
          sync: true,
        ).then((error) {
          expect(error, isNull);
          completions.add('B');
        });
    await Future<void>.delayed(Duration.zero);

    final reset2 = SeriousPython.resetRuntime().then((_) {
      completions.add('R2');
    });

    await Future.wait([
      runA,
      reset1,
      runB,
      reset2,
    ]).timeout(const Duration(seconds: 30));
    expect(completions, ['A', 'R1', 'B', 'R2']);
  });
}
