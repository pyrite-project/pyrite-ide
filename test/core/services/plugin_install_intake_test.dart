import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/plugin_install_link.dart';
import 'package:pyrite_ide/core/services/plugin_install_intake.dart';

void main() {
  late List<PluginInstallIntent> opened;
  late StreamController<String> links;

  setUp(() {
    opened = [];
    links = StreamController<String>();
  });

  tearDown(() => links.close());

  PluginInstallIntake intake({String? initial, bool initialFails = false}) =>
      PluginInstallIntake(
        onIntent: opened.add,
        initialLink: () async {
          if (initialFails) throw UnimplementedError();
          return initial;
        },
        linkStream: links.stream,
      );

  const registryLink =
      'pyride://plugin/install?id=com.example.hello&version=1.2.0'
      '&origin=https%3A%2F%2Fforum.example';

  test('opens an install tab for a link the IDE was launched with', () async {
    await intake().start([registryLink]);

    expect(opened, hasLength(1));
    expect(opened.single, isA<RegistryInstallIntent>());
  });

  test('opens a package file passed as a launch argument', () async {
    await intake().start(['/tmp/hello.pyrix']);

    expect(opened, [const LocalInstallIntent('/tmp/hello.pyrix')]);
  });

  test('keeps a Windows path with spaces intact', () async {
    await intake().start([r'C:\Users\me\my plugin.pyrix']);

    expect(opened, [const LocalInstallIntent(r'C:\Users\me\my plugin.pyrix')]);
  });

  test('ignores launch arguments that are not install requests', () async {
    await intake().start(['--verbose', '/tmp/notes.txt', '']);

    expect(opened, isEmpty);
  });

  test('handles the link that started the app', () async {
    await intake(initial: registryLink).start(const []);

    expect(opened, hasLength(1));
  });

  test('keeps working on platforms without an initial link', () async {
    await intake(initialFails: true).start(const []);
    links.add(registryLink);
    await pumpEventQueue();

    expect(opened, hasLength(1));
  });

  test('handles links and files that arrive while running', () async {
    await intake().start(const []);

    links
      ..add(registryLink)
      ..add(Uri.file('/tmp/other.pyrix').toString())
      ..add('https://example.com/not-for-us');
    await pumpEventQueue();

    expect(opened, hasLength(2));
    expect(opened.last, const LocalInstallIntent('/tmp/other.pyrix'));
  });

  test('starting twice does not double-handle later links', () async {
    final service = intake();
    await service.start(const []);
    await service.start(const []);

    links.add(registryLink);
    await pumpEventQueue();

    expect(opened, hasLength(1));
  });

  test('stops listening after dispose', () async {
    final service = intake();
    await service.start(const []);
    await service.dispose();

    links.add(registryLink);
    await pumpEventQueue();

    expect(opened, isEmpty);
  });
}
