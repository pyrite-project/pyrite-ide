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

  test('a changed plugin value takes an editable control back', () {
    host.effectiveProps({'id': 'query', 'value': 'alpha'});
    host.registerComponent('query', 'TextField', {
      'id': 'query',
      'value': 'alpha',
    });
    host.recordEdit('query', 'beta', (_) {});
    expect(host.displayValue('query', 'alpha'), 'beta');

    // The plugin has not reacted yet: the user's input stays.
    host.effectiveProps({'id': 'query', 'value': 'alpha'});
    host.registerComponent('query', 'TextField', {
      'id': 'query',
      'value': 'alpha',
    });
    expect(host.displayValue('query', 'alpha'), 'beta');

    // The plugin renders a different value: it owns the control again.
    host.effectiveProps({'id': 'query', 'value': 'gamma'});
    expect(host.displayValue('query', 'gamma'), 'gamma');
  });

  test(
    'a plugin echo acknowledges the edit so a later snapshot can reset it',
    () {
      host.effectiveProps({'id': 'flag', 'value': false});
      host.registerComponent('flag', 'Checkbox', {
        'id': 'flag',
        'value': false,
      });
      host.flush('flag', true, (_) {});
      expect(host.displayValue('flag', false), isTrue);

      // The plugin renders the toggled value: both sides agree, so the local
      // override is dropped without changing what is on screen.
      host.effectiveProps({'id': 'flag', 'value': true});
      expect(host.displayValue('flag', true), isTrue);

      // A later snapshot is free to reset the control.
      host.effectiveProps({'id': 'flag', 'value': false});
      expect(host.displayValue('flag', false), isFalse);
    },
  );

  test('an echo of an earlier emitted value keeps newer local input', () {
    host.effectiveProps({'id': 'query', 'value': ''});
    host.registerComponent('query', 'TextField', {'id': 'query', 'value': ''});
    host.flush('query', 'a', (_) {});
    host.recordEdit('query', 'ab', (_) {});

    // The plugin echoes the value emitted before the latest keystroke.
    host.effectiveProps({'id': 'query', 'value': 'a'});
    expect(host.displayValue('query', 'a'), 'ab');

    // A genuinely new plugin value still wins.
    host.effectiveProps({'id': 'query', 'value': 'z'});
    expect(host.displayValue('query', 'z'), 'z');
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
