import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/sdk/component_schema.dart';
import 'package:pyrite_ide/core/sdk/renderer_registry.dart';

Map<String, dynamic> _node(
  String type, {
  Map<String, dynamic>? props,
  List<Map<String, dynamic>>? children,
  Map<String, dynamic>? events,
}) => {'type': type, 'props': ?props, 'children': ?children, 'events': ?events};

void main() {
  late ComponentRegistry registry;

  setUp(() => registry = ComponentRegistry());

  group('component validation', () {
    test('a well-formed tree validates', () {
      final result = registry.validate(
        _node(
          'Column',
          props: {'gap': 8},
          children: [
            _node('Text', props: {'value': 'hello', 'style': 'title'}),
            _node(
              'Button',
              props: {'id': 'ok', 'label': 'OK', 'variant': 'primary'},
              events: {'press': 'cb-1'},
            ),
          ],
        ),
      );
      expect(result.isValid, isTrue, reason: '${result.diagnostics}');
      expect(result.nodeCount, 3);
    });

    test('every component accepts the common optional id property', () {
      final result = registry.validate(
        _node('Text', props: {'id': 'heading', 'value': 'hello'}),
      );
      expect(result.isValid, isTrue, reason: '${result.diagnostics}');
    });

    test('unknown component is reported with its path', () {
      final result = registry.validate(
        _node('Column', children: [_node('Frobnicator')]),
      );
      expect(result.isValid, isFalse);
      expect(result.diagnostics.single.path, 'root.children[0]');
      expect(result.diagnostics.single.message, contains('unknown component'));
    });

    test('unknown property is reported without failing the whole tree', () {
      final result = registry.validate(
        _node('Text', props: {'value': 'x', 'colour': 'red'}),
      );
      expect(result.diagnostics.single.path, 'root.props.colour');
      expect(result.diagnostics.single.message, contains('unknown property'));
    });

    test('missing required property is reported', () {
      final result = registry.validate(_node('Text'));
      expect(result.diagnostics.single.path, 'root.props.value');
      expect(
        result.diagnostics.single.message,
        contains('missing required property'),
      );
    });

    test('wrong property type is reported', () {
      final result = registry.validate(_node('Text', props: {'value': 42}));
      expect(result.diagnostics.single.message, 'expected string');
    });

    test('value outside a closed set is reported', () {
      final result = registry.validate(
        _node('Text', props: {'value': 'x', 'style': 'enormous'}),
      );
      expect(result.diagnostics.single.message, contains('expected one of'));
    });

    test('unknown event is reported', () {
      final result = registry.validate(
        _node(
          'Button',
          props: {'id': 'b', 'label': 'B'},
          events: {'hover': 'c'},
        ),
      );
      expect(result.diagnostics.single.path, 'root.events.hover');
      expect(result.diagnostics.single.message, contains('unknown event'));
    });

    test('children under a leaf component are rejected', () {
      final result = registry.validate(
        _node('Text', props: {'value': 'x'}, children: [_node('Text')]),
      );
      expect(result.diagnostics.first.path, 'root.children');
      expect(
        result.diagnostics.first.message,
        contains('cannot contain children'),
      );
    });

    test('illegal child type for a restricted parent is rejected', () {
      final result = registry.validate(
        _node(
          'Tabs',
          children: [
            _node('Text', props: {'value': 'not a tab'}),
          ],
        ),
      );
      expect(result.diagnostics.single.message, contains('cannot contain'));
      expect(result.diagnostics.single.message, contains('Tab'));
    });

    test('a single-child component rejects extra children', () {
      final result = registry.validate(
        _node(
          'Tooltip',
          props: {'message': 'hi'},
          children: [
            _node('Text', props: {'value': 'a'}),
            _node('Text', props: {'value': 'b'}),
          ],
        ),
      );
      expect(
        result.diagnostics.any((d) => d.message.contains('at most one child')),
        isTrue,
      );
    });

    test('several problems are all collected', () {
      final result = registry.validate(
        _node(
          'Column',
          children: [
            _node('Text'), // missing value
            _node('Nope'), // unknown component
          ],
        ),
      );
      expect(result.diagnostics, hasLength(2));
    });
  });

  group('limits', () {
    test('depth beyond the limit is rejected', () {
      // Build a Column nested 6 deep against a limit of 4.
      Map<String, dynamic> nest(int depth) => depth == 0
          ? _node('Text', props: {'value': 'leaf'})
          : _node('Column', children: [nest(depth - 1)]);
      final result = registry.validate(
        nest(6),
        limits: const ComponentLimits(maxDepth: 4),
      );
      expect(
        result.diagnostics.any((d) => d.message.contains('deeper than 4')),
        isTrue,
      );
    });

    test('node count beyond the limit is rejected once', () {
      final result = registry.validate(
        _node(
          'Column',
          children: [
            for (var i = 0; i < 10; i++) _node('Text', props: {'value': '$i'}),
          ],
        ),
        limits: const ComponentLimits(maxNodes: 5),
      );
      expect(
        result.diagnostics.where((d) => d.message.contains('exceeds 5 nodes')),
        hasLength(1),
      );
    });
  });

  group('renderer registry', () {
    test('every renderer token is known and maps to a real component', () {
      final renderers = RendererRegistry();
      for (final token in RendererTokens.all) {
        expect(renderers.isKnown(token), isTrue, reason: token);
      }
      expect(renderers.validateAgainst(registry), isEmpty);
    });

    test('node fields required by a renderer are enforced', () {
      final renderers = RendererRegistry();
      final missing = renderers.validateNodes(RendererTokens.outline, [
        {'id': 'n1', 'label': 'ok'},
        {'id': 'n2'}, // no label
      ]);
      expect(missing.single.path, 'nodes[1].label');
    });

    test('an unknown renderer token is reported', () {
      final renderers = RendererRegistry();
      final result = renderers.validateNodes('native.hologram', const []);
      expect(result.single.message, contains('unknown renderer'));
    });
  });
}
