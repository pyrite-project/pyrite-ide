import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';

class _Host implements ComponentMethodHostEntry {
  _Host(this.instance, this.value);

  @override
  final ViewInstanceId instance;
  final Object? value;

  @override
  Future<Object?> invokeComponentMethod(
    String componentId,
    String method,
    Map<String, dynamic> arguments,
  ) async => value;
}

ViewInstanceId _instance(
  String instanceId, {
  String pluginId = 'plugin.one',
  String sessionId = 'session.one',
}) => ViewInstanceId(
  pluginId: pluginId,
  sessionId: sessionId,
  viewId: 'view',
  instanceId: instanceId,
);

void main() {
  test('hosts are isolated by the complete view instance identity', () async {
    final registry = ComponentMethodRegistry();
    final first = _instance('first');
    final second = _instance('second');
    registry.attach(first, _Host(first, 1));
    registry.attach(second, _Host(second, 2));

    expect(await registry.invoke(first, 'c', 'm', const {}), 1);
    expect(await registry.invoke(second, 'c', 'm', const {}), 2);
  });

  test('detach only removes the host that is still attached', () async {
    final registry = ComponentMethodRegistry();
    final instance = _instance('first');
    final oldHost = _Host(instance, 1);
    final currentHost = _Host(instance, 2);
    registry.attach(instance, oldHost);
    registry.attach(instance, currentHost);
    registry.detach(instance, oldHost);

    expect(await registry.invoke(instance, 'c', 'm', const {}), 2);
  });

  test(
    'session, plugin, and global cleanup remove the intended hosts',
    () async {
      final registry = ComponentMethodRegistry();
      final oldSession = _instance('old');
      final newSession = _instance('new', sessionId: 'session.two');
      final otherPlugin = _instance('other', pluginId: 'plugin.two');
      registry.attach(oldSession, _Host(oldSession, 1));
      registry.attach(newSession, _Host(newSession, 2));
      registry.attach(otherPlugin, _Host(otherPlugin, 3));

      registry.clearSession('plugin.one', 'session.one');
      await expectLater(
        registry.invoke(oldSession, 'c', 'm', const {}),
        throwsA(isA<ComponentMethodException>()),
      );
      expect(await registry.invoke(newSession, 'c', 'm', const {}), 2);

      registry.clearPlugin('plugin.one');
      await expectLater(
        registry.invoke(newSession, 'c', 'm', const {}),
        throwsA(isA<ComponentMethodException>()),
      );
      expect(await registry.invoke(otherPlugin, 'c', 'm', const {}), 3);

      registry.clear();
      await expectLater(
        registry.invoke(otherPlugin, 'c', 'm', const {}),
        throwsA(isA<ComponentMethodException>()),
      );
    },
  );
}
