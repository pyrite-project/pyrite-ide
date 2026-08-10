/// Schema version of the common component layer.
///
/// Bumped when component props or events change incompatibly, so a plugin built
/// against an older host can be told to upgrade rather than failing obscurely.
const int componentSchemaVersion = 1;

/// Limits guarding against pathological component trees from a plugin.
class ComponentLimits {
  const ComponentLimits({this.maxDepth = 32, this.maxNodes = 5000});

  final int maxDepth;
  final int maxNodes;
}

/// Value type of a component property.
enum PropType { string, number, boolean, stringList, map, any }

/// Declaration of one component property.
class PropSpec {
  const PropSpec(
    this.type, {
    this.required = false,
    this.defaultValue,
    this.allowed,
  });

  final PropType type;
  final bool required;
  final Object? defaultValue;

  /// Optional closed set of legal values (for enum-like string props).
  final Set<String>? allowed;

  /// Whether [value] satisfies this spec's type, returning null when valid or a
  /// human-readable reason when not.
  String? validate(Object? value) {
    if (value == null) return required ? 'missing required value' : null;
    final typeError = switch (type) {
      PropType.string => value is String ? null : 'expected string',
      PropType.number => value is num ? null : 'expected number',
      PropType.boolean => value is bool ? null : 'expected boolean',
      PropType.stringList =>
        value is List && value.every((e) => e is String)
            ? null
            : 'expected list of strings',
      PropType.map => value is Map ? null : 'expected map',
      PropType.any => null,
    };
    if (typeError != null) return typeError;
    if (allowed != null && value is String && !allowed!.contains(value)) {
      return 'expected one of ${allowed!.toList()..sort()}';
    }
    return null;
  }
}

/// How a component may contain other components.
enum ChildPolicy {
  /// No children allowed (leaf).
  none,

  /// Exactly one child.
  single,

  /// Any number of children.
  many,
}

/// Declaration of one component: its props, events, and nesting rules.
class ComponentSpec {
  const ComponentSpec({
    required this.name,
    this.props = const {},
    this.events = const {},
    this.children = ChildPolicy.none,
    this.allowedChildren,
  });

  final String name;
  final Map<String, PropSpec> props;

  /// Event names this component can emit, mapped to a short description.
  final Map<String, String> events;
  final ChildPolicy children;

  /// When set, only these component names may be direct children (e.g. Tabs
  /// only accepts Tab entries).
  final Set<String>? allowedChildren;
}

/// One validation problem, addressed by a path into the component tree.
class ComponentDiagnostic {
  const ComponentDiagnostic({required this.path, required this.message});

  /// Dotted path such as `root.children[0].props.label`.
  final String path;
  final String message;

  @override
  String toString() => '$path: $message';

  Map<String, dynamic> toJson() => {'path': path, 'message': message};
}

/// Result of validating a component tree.
class ComponentValidation {
  const ComponentValidation(this.diagnostics, {this.nodeCount = 0});

  final List<ComponentDiagnostic> diagnostics;
  final int nodeCount;

  bool get isValid => diagnostics.isEmpty;
}

/// Registry of the common components a plugin may compose.
///
/// The schema is a stable abstraction: prop names are host-defined and never map
/// straight onto Flutter constructor arguments, so the widget layer can change
/// without breaking plugins.
class ComponentRegistry {
  ComponentRegistry([Iterable<ComponentSpec>? specs]) {
    for (final spec in specs ?? _defaults) {
      _specs[spec.name] = spec;
    }
  }

  final Map<String, ComponentSpec> _specs = {};

  ComponentSpec? lookup(String name) => _specs[name];
  bool isKnown(String name) => _specs.containsKey(name);
  Iterable<String> get names => _specs.keys;

  void register(ComponentSpec spec) => _specs[spec.name] = spec;

  /// Validates [node] as the root of a component tree.
  ///
  /// Collects every problem instead of failing on the first, so the host can
  /// render one error boundary listing what a plugin got wrong.
  ComponentValidation validate(
    Map<String, dynamic> node, {
    ComponentLimits limits = const ComponentLimits(),
  }) {
    final diagnostics = <ComponentDiagnostic>[];
    var count = 0;

    void walk(Map<String, dynamic> current, String path, int depth) {
      count++;
      if (count > limits.maxNodes) {
        if (count == limits.maxNodes + 1) {
          diagnostics.add(
            ComponentDiagnostic(
              path: path,
              message: 'component tree exceeds ${limits.maxNodes} nodes',
            ),
          );
        }
        return;
      }
      if (depth > limits.maxDepth) {
        diagnostics.add(
          ComponentDiagnostic(
            path: path,
            message: 'component nesting deeper than ${limits.maxDepth}',
          ),
        );
        return;
      }

      final type = current['type']?.toString();
      if (type == null || type.isEmpty) {
        diagnostics.add(
          ComponentDiagnostic(path: path, message: 'missing component type'),
        );
        return;
      }
      final spec = _specs[type];
      if (spec == null) {
        diagnostics.add(
          ComponentDiagnostic(path: path, message: 'unknown component "$type"'),
        );
        return;
      }

      final rawProps = current['props'];
      final props = rawProps is Map
          ? rawProps.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{};
      for (final entry in props.entries) {
        final propSpec =
            spec.props[entry.key] ??
            (entry.key == 'id' ? const PropSpec(PropType.string) : null);
        if (propSpec == null) {
          diagnostics.add(
            ComponentDiagnostic(
              path: '$path.props.${entry.key}',
              message: 'unknown property for "$type"',
            ),
          );
          continue;
        }
        final error = propSpec.validate(entry.value);
        if (error != null) {
          diagnostics.add(
            ComponentDiagnostic(
              path: '$path.props.${entry.key}',
              message: error,
            ),
          );
        }
      }
      for (final entry in spec.props.entries) {
        if (entry.value.required && !props.containsKey(entry.key)) {
          diagnostics.add(
            ComponentDiagnostic(
              path: '$path.props.${entry.key}',
              message: 'missing required property for "$type"',
            ),
          );
        }
      }

      final rawEvents = current['events'];
      if (rawEvents is Map) {
        for (final key in rawEvents.keys) {
          if (!spec.events.containsKey(key.toString())) {
            diagnostics.add(
              ComponentDiagnostic(
                path: '$path.events.$key',
                message: 'unknown event for "$type"',
              ),
            );
          }
        }
      }

      final rawChildren = current['children'];
      final children = rawChildren is List
          ? [
              for (final child in rawChildren)
                if (child is Map)
                  child.map((k, v) => MapEntry(k.toString(), v)),
            ]
          : const <Map<String, dynamic>>[];

      if (children.isNotEmpty && spec.children == ChildPolicy.none) {
        diagnostics.add(
          ComponentDiagnostic(
            path: '$path.children',
            message: '"$type" cannot contain children',
          ),
        );
        return;
      }
      if (spec.children == ChildPolicy.single && children.length > 1) {
        diagnostics.add(
          ComponentDiagnostic(
            path: '$path.children',
            message: '"$type" accepts at most one child',
          ),
        );
      }
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        final childPath = '$path.children[$i]';
        final childType = child['type']?.toString();
        if (spec.allowedChildren != null &&
            childType != null &&
            !spec.allowedChildren!.contains(childType)) {
          diagnostics.add(
            ComponentDiagnostic(
              path: childPath,
              message:
                  '"$type" cannot contain "$childType"; allowed: '
                  '${spec.allowedChildren!.toList()..sort()}',
            ),
          );
          continue;
        }
        walk(child, childPath, depth + 1);
      }
    }

    walk(node, 'root', 1);
    return ComponentValidation(diagnostics, nodeCount: count);
  }

  /// The first batch of common components.
  static final List<ComponentSpec> _defaults = [
    // -- Layout --------------------------------------------------------------
    const ComponentSpec(
      name: 'Row',
      props: {
        'gap': PropSpec(PropType.number),
        'align': PropSpec(
          PropType.string,
          allowed: {'start', 'center', 'end', 'stretch'},
        ),
        'justify': PropSpec(
          PropType.string,
          allowed: {'start', 'center', 'end', 'spaceBetween', 'spaceAround'},
        ),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Column',
      props: {
        'gap': PropSpec(PropType.number),
        'align': PropSpec(
          PropType.string,
          allowed: {'start', 'center', 'end', 'stretch'},
        ),
        'justify': PropSpec(
          PropType.string,
          allowed: {'start', 'center', 'end', 'spaceBetween', 'spaceAround'},
        ),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Flex',
      props: {
        'direction': PropSpec(
          PropType.string,
          allowed: {'horizontal', 'vertical'},
        ),
        'flex': PropSpec(PropType.number),
        'gap': PropSpec(PropType.number),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Grid',
      props: {
        'columns': PropSpec(PropType.number, required: true),
        'gap': PropSpec(PropType.number),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Wrap',
      props: {
        'gap': PropSpec(PropType.number),
        'runGap': PropSpec(PropType.number),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'SplitView',
      props: {
        'id': PropSpec(PropType.string),
        'direction': PropSpec(
          PropType.string,
          allowed: {'horizontal', 'vertical'},
        ),
        'initialRatio': PropSpec(PropType.number),
      },
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Tabs',
      props: {
        'id': PropSpec(PropType.string),
        'selected': PropSpec(PropType.string),
      },
      events: {'change': 'the selected tab changed'},
      children: ChildPolicy.many,
      allowedChildren: {'Tab'},
    ),
    const ComponentSpec(
      name: 'Tab',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'label': PropSpec(PropType.string, required: true),
        'icon': PropSpec(PropType.string),
      },
      children: ChildPolicy.single,
    ),
    const ComponentSpec(
      name: 'Section',
      props: {
        'id': PropSpec(PropType.string),
        'title': PropSpec(PropType.string),
        'collapsible': PropSpec(PropType.boolean),
        'collapsed': PropSpec(PropType.boolean),
      },
      events: {'toggle': 'the section was expanded or collapsed'},
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Toolbar',
      props: {'dense': PropSpec(PropType.boolean)},
      children: ChildPolicy.many,
    ),

    // -- Content -------------------------------------------------------------
    const ComponentSpec(
      name: 'Card',
      // props: {
      //   'elevation': PropSpec(PropType.number),
      //   'borderRadius': PropSpec(PropType.number),
      //   'padding': PropSpec(PropType.number),
      // },
      children: ChildPolicy.single,
    ),
    const ComponentSpec(
      name: 'Text',
      props: {
        'value': PropSpec(PropType.string, required: true),
        'style': PropSpec(
          PropType.string,
          allowed: {'body', 'caption', 'title', 'heading', 'code'},
        ),
        'muted': PropSpec(PropType.boolean),
        'maxLines': PropSpec(PropType.number),
      },
    ),
    const ComponentSpec(
      name: 'Icon',
      props: {
        'name': PropSpec(PropType.string, required: true),
        'size': PropSpec(PropType.number),
      },
    ),
    const ComponentSpec(
      name: 'Image',
      props: {
        'id': PropSpec(PropType.string),
        'src': PropSpec(PropType.string, required: true),
        'width': PropSpec(PropType.number),
        'height': PropSpec(PropType.number),
        'fit': PropSpec(
          PropType.string,
          allowed: {'contain', 'cover', 'fill', 'none'},
        ),
      },
    ),
    const ComponentSpec(
      name: 'Video',
      props: {
        'id': PropSpec(PropType.string),
        'src': PropSpec(PropType.string, required: true),
        'width': PropSpec(PropType.number),
        'height': PropSpec(PropType.number),
        'fit': PropSpec(
          PropType.string,
          allowed: {'contain', 'cover', 'fill', 'none'},
        ),
        'autoplay': PropSpec(PropType.boolean),
        'looping': PropSpec(PropType.boolean),
        'muted': PropSpec(PropType.boolean),
        'showControls': PropSpec(PropType.boolean),
      },
    ),
    const ComponentSpec(
      name: 'Markdown',
      props: {
        'id': PropSpec(PropType.string),
        'value': PropSpec(PropType.string, required: true),
      },
      events: {'linkTap': 'a markdown link was activated'},
    ),
    const ComponentSpec(
      name: 'CodeBlock',
      props: {
        'code': PropSpec(PropType.string, required: true),
        'language': PropSpec(PropType.string),
        'showLineNumbers': PropSpec(PropType.boolean),
      },
    ),
    const ComponentSpec(
      name: 'Badge',
      props: {
        'label': PropSpec(PropType.string, required: true),
        'tone': PropSpec(
          PropType.string,
          allowed: {'neutral', 'info', 'success', 'warning', 'danger'},
        ),
      },
    ),

    // -- Input ---------------------------------------------------------------
    const ComponentSpec(
      name: 'TextField',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.string),
        'placeholder': PropSpec(PropType.string),
        'label': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
        'multiline': PropSpec(PropType.boolean),
      },
      events: {
        'change': 'the text changed (debounced by the host)',
        'submit': 'the user confirmed the value',
      },
    ),
    const ComponentSpec(
      name: 'NumberField',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.number),
        'min': PropSpec(PropType.number),
        'max': PropSpec(PropType.number),
        'step': PropSpec(PropType.number),
        'label': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'change': 'the number changed', 'submit': 'value confirmed'},
    ),
    const ComponentSpec(
      name: 'Select',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.string),
        'options': PropSpec(PropType.any, required: true),
        'label': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'change': 'the selection changed'},
    ),
    const ComponentSpec(
      name: 'Checkbox',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.boolean),
        'label': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'change': 'the checked state changed'},
    ),
    const ComponentSpec(
      name: 'Switch',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.boolean),
        'label': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'change': 'the switch was toggled'},
    ),
    const ComponentSpec(
      name: 'Slider',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'value': PropSpec(PropType.number),
        'min': PropSpec(PropType.number),
        'max': PropSpec(PropType.number),
        'step': PropSpec(PropType.number),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'change': 'the value changed'},
    ),

    // -- Actions -------------------------------------------------------------
    const ComponentSpec(
      name: 'Button',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'label': PropSpec(PropType.string, required: true),
        'icon': PropSpec(PropType.string),
        'variant': PropSpec(
          PropType.string,
          allowed: {'primary', 'secondary', 'ghost', 'danger'},
        ),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'press': 'the button was pressed'},
    ),
    const ComponentSpec(
      name: 'IconButton',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'icon': PropSpec(PropType.string, required: true),
        'tooltip': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'press': 'the button was pressed'},
    ),
    const ComponentSpec(
      name: 'Menu',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'items': PropSpec(PropType.any, required: true),
        'label': PropSpec(PropType.string),
        'icon': PropSpec(PropType.string),
        'tooltip': PropSpec(PropType.string),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
        'iconOnly': PropSpec(PropType.boolean, defaultValue: false),
        'alignment': PropSpec(
          PropType.string,
          allowed: {'bottomStart', 'bottomEnd', 'topStart', 'topEnd'},
        ),
        'offsetX': PropSpec(PropType.number),
        'offsetY': PropSpec(PropType.number),
        'useRootOverlay': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'select': 'a menu item was chosen'},
      children: ChildPolicy.single,
    ),
    const ComponentSpec(
      name: 'MenuBar',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'items': PropSpec(PropType.any, required: true),
      },
      events: {'select': 'a menu item was chosen'},
    ),
    const ComponentSpec(
      name: 'ContextMenu',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'items': PropSpec(PropType.any, required: true),
        'enabled': PropSpec(PropType.boolean, defaultValue: true),
      },
      events: {'select': 'a menu item was chosen'},
      children: ChildPolicy.single,
    ),
    const ComponentSpec(
      name: 'Dropdown',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'label': PropSpec(PropType.string),
        'items': PropSpec(PropType.any, required: true),
      },
      events: {'select': 'an item was chosen'},
    ),
    const ComponentSpec(
      name: 'Dialog',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'title': PropSpec(PropType.string),
        'open': PropSpec(PropType.boolean),
      },
      events: {'close': 'the dialog was dismissed'},
      children: ChildPolicy.many,
    ),
    const ComponentSpec(
      name: 'Tooltip',
      props: {'message': PropSpec(PropType.string, required: true)},
      children: ChildPolicy.single,
    ),

    // -- Data ----------------------------------------------------------------
    // Rows build lazily from the visible range; `itemCount` may exceed the
    // number of loaded `items`, with gaps filled via the requestRange event.
    const ComponentSpec(
      name: 'VirtualList',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'items': PropSpec(PropType.any),
        'itemCount': PropSpec(PropType.number),
        'itemHeight': PropSpec(PropType.number),
        'selectedId': PropSpec(PropType.string),
        'emptyLabel': PropSpec(PropType.string),
      },
      events: {
        'select': 'a row was selected',
        'activate': 'a row was activated (double click / Enter)',
        'requestRange': 'the visible range needs more data',
        'contextMenuRequest': 'a row requested a dynamic context menu',
      },
    ),
    // Backed by the bundled super_tree package (TreeController drives
    // expansion, search, and context menus) without exposing its API.
    const ComponentSpec(
      name: 'TreeView',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'nodes': PropSpec(PropType.any),
        'expandedIds': PropSpec(PropType.stringList),
        'selectedId': PropSpec(PropType.string),
        'indent': PropSpec(PropType.number),
        'searchable': PropSpec(PropType.boolean),
        'emptyLabel': PropSpec(PropType.string),
      },
      events: {
        'select': 'a node was selected',
        'activate': 'a node was activated',
        'expand': 'a node was expanded',
        'collapse': 'a node was collapsed',
        'requestChildren': 'an unloaded node needs children',
        'contextMenu': 'a node was right-clicked',
        'contextMenuRequest': 'a node requested a dynamic context menu',
      },
    ),
    // Backed by material_table_view: rows build lazily, and columns support
    // fixed width, flex, and freezing. Column entries are
    // `{id, label, width?, flex?, frozen?, sticky?}` maps.
    const ComponentSpec(
      name: 'DataTable',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'columns': PropSpec(PropType.any, required: true),
        'rows': PropSpec(PropType.any),
        'rowCount': PropSpec(PropType.number),
        'rowHeight': PropSpec(PropType.number),
        'showHeader': PropSpec(PropType.boolean, defaultValue: true),
        'selectedId': PropSpec(PropType.string),
        'sortColumn': PropSpec(PropType.string),
        'sortAscending': PropSpec(PropType.boolean),
        'emptyLabel': PropSpec(PropType.string),
      },
      events: {
        'select': 'a row was selected',
        'activate': 'a row was activated',
        'sort': 'a column header was clicked',
        'requestRange': 'the visible range needs more rows',
        'contextMenuRequest': 'a row requested a dynamic context menu',
      },
    ),
    const ComponentSpec(
      name: 'PropertyGrid',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'entries': PropSpec(PropType.any, required: true),
        'selectedId': PropSpec(PropType.string),
        'indent': PropSpec(PropType.number),
        'emptyLabel': PropSpec(PropType.string),
      },
      events: {
        'select': 'a property was selected',
        'expand': 'a property was expanded',
        'collapse': 'a property was collapsed',
        'requestChildren': 'an unloaded property needs children',
        'activate': 'a property was activated',
        'contextMenuRequest': 'a property requested a dynamic context menu',
      },
    ),

    // -- Page scaffolding ----------------------------------------------------
    // A title bar for a free component tree. Actions are expressed as children
    // (restricted to IconButton/Menu/Dropdown), reusing the same restricted
    // parent pattern as Tabs->Tab so validation, events, and invoke work with
    // no new machinery. It renders only the plugin's own action children; the
    // manifest/title command menu stays exclusive to the renderer-driven path.
    const ComponentSpec(
      name: 'AppBar',
      props: {
        'id': PropSpec(PropType.string),
        'title': PropSpec(PropType.string),
      },
      children: ChildPolicy.many,
      allowedChildren: {'IconButton', 'Menu', 'Dropdown'},
    ),
    // Minimal two-slot page skeleton: an optional AppBar (only when it is the
    // first child) plus a body that receives a bounded main-axis extent so
    // scrollable children (VirtualList, DataTable, Flex) work.
    const ComponentSpec(
      name: 'Scaffold',
      props: {'id': PropSpec(PropType.string)},
      children: ChildPolicy.many,
    ),
    // High-performance interactive custom-draw surface. Interaction (pan/zoom,
    // hover highlight, drag preview, rubber-band) is host-local; only the
    // semantic events below cross the process boundary, throttled by the host.
    const ComponentSpec(
      name: 'Canvas',
      props: {
        'id': PropSpec(PropType.string, required: true),
        'width': PropSpec(PropType.number),
        'height': PropSpec(PropType.number),
        'ops': PropSpec(PropType.any),
        'interactive': PropSpec(PropType.boolean, defaultValue: false),
        'viewport': PropSpec(PropType.map),
      },
      events: {
        'tap': 'a tap/click on the canvas',
        'drag': 'a drag gesture (start/update/end)',
        'hover': 'the pointer hovered over the canvas (throttled)',
        'pointer': 'a low-level pointer event (throttled)',
      },
    ),
  ];
}
