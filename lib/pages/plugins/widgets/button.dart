import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart' as rfw;

Widget buildFilledButton(BuildContext context, rfw.DataSource source) {
  return FilledButton(
    onPressed: source.voidHandler(<Object>['onPressed']),
    onLongPress: source.voidHandler(<Object>['onLongPress']),
    onHover: source.handler<ValueChanged<bool>>(
      <Object>['onHover'],
      (trigger) =>
          (bool value) => trigger(<String, Object?>{'value': value}),
    ),
    onFocusChange: source.handler<ValueChanged<bool>>(
      <Object>['onFocusChange'],
      (trigger) =>
          (bool value) => trigger(<String, Object?>{'value': value}),
    ),
    style: _decodeButtonStyle(source),
    autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
    clipBehavior:
        rfw.ArgumentDecoders.enumValue<Clip>(Clip.values, source, <Object>[
          'clipBehavior',
        ]) ??
        Clip.none,
    child: source.child(<Object>['child']),
  );
}

Widget buildElevatedButton(BuildContext context, rfw.DataSource source) {
  return ElevatedButton(
    onPressed: source.voidHandler(<Object>['onPressed']),
    onLongPress: source.voidHandler(<Object>['onLongPress']),
    onHover: source.handler<ValueChanged<bool>>(
      <Object>['onHover'],
      (trigger) =>
          (bool value) => trigger(<String, Object?>{'value': value}),
    ),
    onFocusChange: source.handler<ValueChanged<bool>>(
      <Object>['onFocusChange'],
      (trigger) =>
          (bool value) => trigger(<String, Object?>{'value': value}),
    ),
    style: _decodeButtonStyle(source),
    autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
    clipBehavior:
        rfw.ArgumentDecoders.enumValue<Clip>(Clip.values, source, <Object>[
          'clipBehavior',
        ]) ??
        Clip.none,
    child: source.child(<Object>['child']),
  );
}

ButtonStyle? _decodeButtonStyle(rfw.DataSource source) {
  final foregroundColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'foregroundColor',
  ]);
  final backgroundColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'backgroundColor',
  ]);
  final disabledForegroundColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'disabledForegroundColor',
  ]);
  final disabledBackgroundColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'disabledBackgroundColor',
  ]);
  final shadowColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'shadowColor',
  ]);
  final surfaceTintColor = rfw.ArgumentDecoders.color(source, <Object>[
    'style',
    'surfaceTintColor',
  ]);
  final elevation = _double(source, <Object>['style', 'elevation']);
  final textStyle = rfw.ArgumentDecoders.textStyle(source, <Object>[
    'style',
    'textStyle',
  ]);
  final padding = rfw.ArgumentDecoders.edgeInsets(source, <Object>[
    'style',
    'padding',
  ]);
  final minimumSize = _size(source, <Object>['style', 'minimumSize']);
  final fixedSize = _size(source, <Object>['style', 'fixedSize']);
  final maximumSize = _size(source, <Object>['style', 'maximumSize']);

  if (foregroundColor == null &&
      backgroundColor == null &&
      disabledForegroundColor == null &&
      disabledBackgroundColor == null &&
      shadowColor == null &&
      surfaceTintColor == null &&
      elevation == null &&
      textStyle == null &&
      padding == null &&
      minimumSize == null &&
      fixedSize == null &&
      maximumSize == null) {
    return null;
  }

  return FilledButton.styleFrom(
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
    shadowColor: shadowColor,
    surfaceTintColor: surfaceTintColor,
    elevation: elevation,
    textStyle: textStyle,
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    maximumSize: maximumSize,
  );
}

Size? _size(rfw.DataSource source, List<Object> key) {
  final width =
      _double(source, <Object>[...key, 0]) ??
      _double(source, <Object>[...key, 'width']);
  final height =
      _double(source, <Object>[...key, 1]) ??
      _double(source, <Object>[...key, 'height']);
  if (width == null || height == null) {
    return null;
  }
  return Size(width, height);
}

double? _double(rfw.DataSource source, List<Object> key) {
  return source.v<double>(key) ?? source.v<int>(key)?.toDouble();
}
