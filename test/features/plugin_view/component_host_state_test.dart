import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/component_method_registry.dart';
import 'package:pyrite_ide/core/sdk/view_model_store.dart';
import 'package:pyrite_ide/features/plugin_view/component_host_state.dart';

const _instance = ViewInstanceId(
  pluginId: 'test.plugin',
  sessionId: 'test-session',
  viewId: 'test.view',
  instanceId: 'test-instance',
);

void main() {
  late ComponentHostState host;

  setUp(() => host = ComponentHostState(instance: _instance));
  tearDown(() => host.dispose());

  test(
    'text and number operations update host-local controller state',
    () async {
      host.registerComponent('text', 'TextField', {'value': 'alpha'});
      expect(
        await host.invokeComponentMethod('text', 'get_text', const {}),
        'alpha',
      );
      expect(
        await host.invokeComponentMethod('text', 'set_text', const {
          'text': 'beta',
        }),
        isTrue,
      );
      await host.invokeComponentMethod('text', 'set_selection', const {
        'start': 1,
        'end': 3,
      });
      expect(
        await host.invokeComponentMethod('text', 'get_selection', const {}),
        {'start': 1, 'end': 3},
      );
      await host.invokeComponentMethod('text', 'replace_selection', const {
        'text': 'X',
      });
      expect(
        await host.invokeComponentMethod('text', 'get_text', const {}),
        'bXa',
      );

      host.registerComponent('number', 'NumberField', {
        'value': 2,
        'step': 3,
        'min': 0,
        'max': 6,
      });
      expect(
        await host.invokeComponentMethod('number', 'increment', const {}),
        5,
      );
      expect(
        await host.invokeComponentMethod('number', 'increment', const {}),
        6,
      );
      expect(
        await host.invokeComponentMethod('number', 'decrement', const {}),
        3,
      );
    },
  );

  test('tabs and sections retain imperative local state', () async {
    host.registerComponent('tabs', 'Tabs', {
      'selected': 'one',
      '_tabIds': ['one', 'two'],
    });
    expect(await host.invokeComponentMethod('tabs', 'next', const {}), 'two');
    expect(
      await host.invokeComponentMethod('tabs', 'get_selected', const {}),
      'two',
    );
    expect(
      await host.invokeComponentMethod('tabs', 'previous', const {}),
      'one',
    );

    host.registerComponent('section', 'Section', {'collapsed': false});
    expect(
      await host.invokeComponentMethod('section', 'is_expanded', const {}),
      isTrue,
    );
    await host.invokeComponentMethod('section', 'collapse', const {});
    expect(
      await host.invokeComponentMethod('section', 'is_expanded', const {}),
      isFalse,
    );
    await host.invokeComponentMethod('section', 'toggle', const {});
    expect(
      await host.invokeComponentMethod('section', 'is_expanded', const {}),
      isTrue,
    );
  });

  test('unknown components and methods use stable errors', () async {
    await expectLater(
      host.invokeComponentMethod('missing', 'open', const {}),
      throwsA(
        isA<ComponentMethodException>().having(
          (error) => error.code,
          'code',
          'component_not_found',
        ),
      ),
    );

    host.registerComponent('plain', 'Button', const {});
    await expectLater(
      host.invokeComponentMethod('plain', 'missing', const {}),
      throwsA(
        isA<ComponentMethodException>().having(
          (error) => error.code,
          'code',
          'method_not_supported',
        ),
      ),
    );
  });
}
