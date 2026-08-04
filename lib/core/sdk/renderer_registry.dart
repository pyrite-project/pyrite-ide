import 'package:pyrite_ide/core/sdk/component_schema.dart';

/// The renderer tokens a view contribution may declare.
abstract class RendererTokens {
  static const String tree = 'native.tree';
  static const String virtualList = 'native.virtualList';
  static const String table = 'native.table';
  static const String form = 'native.form';
  static const String markdown = 'native.markdown';
  static const String log = 'native.log';
  static const String outline = 'native.outline';
  static const String variableInspector = 'native.variableInspector';

  static const List<String> all = [
    tree,
    virtualList,
    table,
    form,
    markdown,
    log,
    outline,
    variableInspector,
  ];
}

/// Declaration of a renderer: which component it renders a view's model as, and
/// which node fields that component expects.
///
/// A renderer is a host-provided view shape (tree, table, log…) that consumes
/// the T15 view model directly, as opposed to a free-form component tree.
class RendererSpec {
  const RendererSpec({
    required this.token,
    required this.rootComponent,
    this.requiredNodeFields = const {'id'},
  });

  final String token;

  /// The common component this renderer builds (must exist in the registry).
  final String rootComponent;

  /// Fields every model node must carry for this renderer to draw a row.
  final Set<String> requiredNodeFields;
}

/// Maps renderer tokens to their declarations.
///
/// The Flutter builder side lives in the widget layer; this registry is the
/// Flutter-free contract so it can be validated in isolation.
class RendererRegistry {
  RendererRegistry([Iterable<RendererSpec>? specs]) {
    for (final spec in specs ?? _defaults) {
      _specs[spec.token] = spec;
    }
  }

  final Map<String, RendererSpec> _specs = {};

  RendererSpec? lookup(String token) => _specs[token];
  bool isKnown(String token) => _specs.containsKey(token);
  Iterable<String> get tokens => _specs.keys;

  void register(RendererSpec spec) => _specs[spec.token] = spec;

  /// Checks that every renderer's [RendererSpec.rootComponent] exists in
  /// [components], so a typo can't ship a renderer that cannot build.
  List<ComponentDiagnostic> validateAgainst(ComponentRegistry components) => [
    for (final spec in _specs.values)
      if (!components.isKnown(spec.rootComponent))
        ComponentDiagnostic(
          path: spec.token,
          message: 'renderer root component "${spec.rootComponent}" is unknown',
        ),
  ];

  /// Validates that [nodes] carry the fields [token]'s renderer needs.
  List<ComponentDiagnostic> validateNodes(
    String token,
    List<Map<String, dynamic>> nodes,
  ) {
    final spec = _specs[token];
    if (spec == null) {
      return [
        ComponentDiagnostic(path: token, message: 'unknown renderer "$token"'),
      ];
    }
    final diagnostics = <ComponentDiagnostic>[];
    for (var i = 0; i < nodes.length; i++) {
      for (final field in spec.requiredNodeFields) {
        if (!nodes[i].containsKey(field)) {
          diagnostics.add(
            ComponentDiagnostic(
              path: 'nodes[$i].$field',
              message: 'missing field required by "$token"',
            ),
          );
        }
      }
    }
    return diagnostics;
  }

  static const List<RendererSpec> _defaults = [
    RendererSpec(
      token: RendererTokens.tree,
      rootComponent: 'TreeView',
      requiredNodeFields: {'id', 'label'},
    ),
    RendererSpec(
      token: RendererTokens.virtualList,
      rootComponent: 'VirtualList',
      requiredNodeFields: {'id', 'label'},
    ),
    RendererSpec(
      token: RendererTokens.table,
      rootComponent: 'DataTable',
      requiredNodeFields: {'id'},
    ),
    RendererSpec(
      token: RendererTokens.form,
      rootComponent: 'Column',
      requiredNodeFields: {'id'},
    ),
    RendererSpec(
      token: RendererTokens.markdown,
      rootComponent: 'Markdown',
      requiredNodeFields: {'id'},
    ),
    RendererSpec(
      token: RendererTokens.log,
      rootComponent: 'VirtualList',
      requiredNodeFields: {'id', 'label'},
    ),
    // Outline and the variable inspector are trees with domain-specific rows.
    RendererSpec(
      token: RendererTokens.outline,
      rootComponent: 'TreeView',
      requiredNodeFields: {'id', 'label'},
    ),
    RendererSpec(
      token: RendererTokens.variableInspector,
      rootComponent: 'PropertyGrid',
      requiredNodeFields: {'id', 'name'},
    ),
  ];
}
