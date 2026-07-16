import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart' as rfw;

Widget buildTooltip(BuildContext context, rfw.DataSource source) {
  return Tooltip(
    message: source.v<String>(<Object>['message']) ?? '',
    constraints: rfw.ArgumentDecoders.boxConstraints(source, <Object>[
      'constraints',
    ]),
    padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
    margin: rfw.ArgumentDecoders.edgeInsets(source, <Object>['margin']),
    verticalOffset: _double(source, <Object>['verticalOffset']),
    preferBelow: source.v<bool>(<Object>['preferBelow']),
    excludeFromSemantics: source.v<bool>(<Object>['excludeFromSemantics']),
    textStyle: rfw.ArgumentDecoders.textStyle(source, <Object>['textStyle']),
    textAlign: rfw.ArgumentDecoders.enumValue<TextAlign>(
      TextAlign.values,
      source,
      <Object>['textAlign'],
    ),
    waitDuration: _duration(source, <Object>['waitDuration']),
    showDuration: _duration(source, <Object>['showDuration']),
    exitDuration: _duration(source, <Object>['exitDuration']),
    enableTapToDismiss: source.v<bool>(<Object>['enableTapToDismiss']) ?? true,
    triggerMode: rfw.ArgumentDecoders.enumValue<TooltipTriggerMode>(
      TooltipTriggerMode.values,
      source,
      <Object>['triggerMode'],
    ),
    enableFeedback: source.v<bool>(<Object>['enableFeedback']),
    onTriggered: source.voidHandler(<Object>['onTriggered']),
    ignorePointer: source.v<bool>(<Object>['ignorePointer']),
    child: source.optionalChild(<Object>['child']),
  );
}

Widget buildChip(BuildContext context, rfw.DataSource source) {
  final shape = rfw.ArgumentDecoders.shapeBorder(source, <Object>['shape']);

  return Material(
    type: MaterialType.transparency,
    child: Chip(
      avatar: source.optionalChild(<Object>['avatar']),
      label: source.optionalChild(<Object>['label']) ?? const SizedBox.shrink(),
      labelStyle: rfw.ArgumentDecoders.textStyle(source, <Object>[
        'labelStyle',
      ]),
      labelPadding: rfw.ArgumentDecoders.edgeInsets(source, <Object>[
        'labelPadding',
      ]),
      deleteIcon: source.optionalChild(<Object>['deleteIcon']),
      onDeleted: source.voidHandler(<Object>['onDeleted']),
      deleteIconColor: rfw.ArgumentDecoders.color(source, <Object>[
        'deleteIconColor',
      ]),
      deleteButtonTooltipMessage:
          source.v<String>(<Object>['deleteButtonTooltipMessage']) ??
          source.v<String>(<Object>['tooltip']),
      side: rfw.ArgumentDecoders.borderSide(source, <Object>['side']),
      shape: shape is OutlinedBorder ? shape : null,
      clipBehavior:
          rfw.ArgumentDecoders.enumValue<Clip>(Clip.values, source, <Object>[
            'clipBehavior',
          ]) ??
          Clip.none,
      autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
      backgroundColor: rfw.ArgumentDecoders.color(source, <Object>[
        'backgroundColor',
      ]),
      padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
      visualDensity: rfw.ArgumentDecoders.visualDensity(source, <Object>[
        'visualDensity',
      ]),
      materialTapTargetSize:
          rfw.ArgumentDecoders.enumValue<MaterialTapTargetSize>(
            MaterialTapTargetSize.values,
            source,
            <Object>['materialTapTargetSize'],
          ),
      elevation: _double(source, <Object>['elevation']),
      shadowColor: rfw.ArgumentDecoders.color(source, <Object>['shadowColor']),
      surfaceTintColor: rfw.ArgumentDecoders.color(source, <Object>[
        'surfaceTintColor',
      ]),
      iconTheme: rfw.ArgumentDecoders.iconThemeData(source, <Object>[
        'iconTheme',
      ]),
    ),
  );
}

Widget buildExpansionTile(BuildContext context, rfw.DataSource source) {
  final onExpansionChanged = source.handler<ValueChanged<bool>>(
    <Object>['onExpansionChanged'],
    (trigger) =>
        (bool value) => trigger(<String, Object?>{'value': value}),
  );

  return Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      leading: source.optionalChild(<Object>['leading']),
      title: source.optionalChild(<Object>['title']) ?? const SizedBox.shrink(),
      subtitle: source.optionalChild(<Object>['subtitle']),
      trailing: source.optionalChild(<Object>['trailing']),
      showTrailingIcon: source.v<bool>(<Object>['showTrailingIcon']) ?? true,
      onExpansionChanged: onExpansionChanged,
      initiallyExpanded: source.v<bool>(<Object>['initiallyExpanded']) ?? false,
      maintainState: source.v<bool>(<Object>['maintainState']) ?? false,
      tilePadding: rfw.ArgumentDecoders.edgeInsets(source, <Object>[
        'tilePadding',
      ]),
      expandedCrossAxisAlignment:
          rfw.ArgumentDecoders.enumValue<CrossAxisAlignment>(
            CrossAxisAlignment.values,
            source,
            <Object>['expandedCrossAxisAlignment'],
          ),
      expandedAlignment: rfw.ArgumentDecoders.alignment(source, <Object>[
        'expandedAlignment',
      ]),
      childrenPadding: rfw.ArgumentDecoders.edgeInsets(source, <Object>[
        'childrenPadding',
      ]),
      backgroundColor: rfw.ArgumentDecoders.color(source, <Object>[
        'backgroundColor',
      ]),
      collapsedBackgroundColor: rfw.ArgumentDecoders.color(source, <Object>[
        'collapsedBackgroundColor',
      ]),
      textColor: rfw.ArgumentDecoders.color(source, <Object>['textColor']),
      collapsedTextColor: rfw.ArgumentDecoders.color(source, <Object>[
        'collapsedTextColor',
      ]),
      iconColor: rfw.ArgumentDecoders.color(source, <Object>['iconColor']),
      collapsedIconColor: rfw.ArgumentDecoders.color(source, <Object>[
        'collapsedIconColor',
      ]),
      shape: rfw.ArgumentDecoders.shapeBorder(source, <Object>['shape']),
      collapsedShape: rfw.ArgumentDecoders.shapeBorder(source, <Object>[
        'collapsedShape',
      ]),
      clipBehavior: rfw.ArgumentDecoders.enumValue<Clip>(
        Clip.values,
        source,
        <Object>['clipBehavior'],
      ),
      controlAffinity: rfw.ArgumentDecoders.enumValue<ListTileControlAffinity>(
        ListTileControlAffinity.values,
        source,
        <Object>['controlAffinity'],
      ),
      dense: source.v<bool>(<Object>['dense']),
      visualDensity: rfw.ArgumentDecoders.visualDensity(source, <Object>[
        'visualDensity',
      ]),
      minTileHeight: _double(source, <Object>['minTileHeight']),
      enableFeedback: source.v<bool>(<Object>['enableFeedback']) ?? true,
      enabled: source.v<bool>(<Object>['enabled']) ?? true,
      children: source.childList(<Object>['children']),
    ),
  );
}

Duration? _duration(rfw.DataSource source, List<Object> key) {
  final milliseconds = source.v<int>(key);
  return milliseconds == null ? null : Duration(milliseconds: milliseconds);
}

double? _double(rfw.DataSource source, List<Object> key) {
  return source.v<double>(key) ?? source.v<int>(key)?.toDouble();
}
