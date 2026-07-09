import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart' as rfw;

Widget buildCheckbox(BuildContext context, rfw.DataSource source) {
  final tristate = source.v<bool>(<Object>['tristate']) ?? false;
  final onChanged = source.handler<ValueChanged<bool?>>(
    <Object>['onChanged'],
    (trigger) =>
        (bool? value) => trigger(<String, Object?>{'value': value}),
  );
  return Material(
    type: MaterialType.transparency,
    child: Checkbox(
      value: source.v<bool>(<Object>['value']) ?? (tristate ? null : false),
      tristate: tristate,
      onChanged: onChanged,
      activeColor: rfw.ArgumentDecoders.color(source, <Object>['activeColor']),
      checkColor: rfw.ArgumentDecoders.color(source, <Object>['checkColor']),
      focusColor: rfw.ArgumentDecoders.color(source, <Object>['focusColor']),
      hoverColor: rfw.ArgumentDecoders.color(source, <Object>['hoverColor']),
      splashRadius: _double(source, <Object>['splashRadius']),
      materialTapTargetSize:
          rfw.ArgumentDecoders.enumValue<MaterialTapTargetSize>(
            MaterialTapTargetSize.values,
            source,
            <Object>['materialTapTargetSize'],
          ),
      visualDensity: rfw.ArgumentDecoders.visualDensity(source, <Object>[
        'visualDensity',
      ]),
      autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
      isError: source.v<bool>(<Object>['isError']) ?? false,
      semanticLabel: source.v<String>(<Object>['semanticLabel']),
    ),
  );
}

Widget buildSwitch(BuildContext context, rfw.DataSource source) {
  final onChanged = source.handler<ValueChanged<bool>>(
    <Object>['onChanged'],
    (trigger) =>
        (bool value) => trigger(<String, Object?>{'value': value}),
  );
  return Material(
    type: MaterialType.transparency,
    child: Switch(
      value: source.v<bool>(<Object>['value']) ?? false,
      onChanged: onChanged,
      activeThumbColor:
          rfw.ArgumentDecoders.color(source, <Object>['activeThumbColor']) ??
          rfw.ArgumentDecoders.color(source, <Object>['activeColor']),
      activeTrackColor: rfw.ArgumentDecoders.color(source, <Object>[
        'activeTrackColor',
      ]),
      inactiveThumbColor: rfw.ArgumentDecoders.color(source, <Object>[
        'inactiveThumbColor',
      ]),
      inactiveTrackColor: rfw.ArgumentDecoders.color(source, <Object>[
        'inactiveTrackColor',
      ]),
      focusColor: rfw.ArgumentDecoders.color(source, <Object>['focusColor']),
      hoverColor: rfw.ArgumentDecoders.color(source, <Object>['hoverColor']),
      splashRadius: _double(source, <Object>['splashRadius']),
      materialTapTargetSize:
          rfw.ArgumentDecoders.enumValue<MaterialTapTargetSize>(
            MaterialTapTargetSize.values,
            source,
            <Object>['materialTapTargetSize'],
          ),
      autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
      padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
    ),
  );
}

Widget buildRadioGroup(BuildContext context, rfw.DataSource source) {
  final groupValue = source.v<String>(<Object>['groupValue']) ?? '';
  final onChanged = source.handler<ValueChanged<String?>>(
    <Object>['onChanged'],
    (trigger) =>
        (String? value) => trigger(<String, Object?>{'value': value}),
  );
  final items =
      rfw.ArgumentDecoders.list<_RadioGroupItem>(source, <Object>['items'], (
        itemSource,
        key,
      ) {
        return _RadioGroupItem(
          value: itemSource.v<String>(<Object>[...key, 'value']) ?? '',
          label: itemSource.v<String>(<Object>[...key, 'label']) ?? '',
          subtitle: itemSource.v<String>(<Object>[...key, 'subtitle']),
          enabled: itemSource.v<bool>(<Object>[...key, 'enabled']),
        );
      }) ??
      <_RadioGroupItem>[];

  return Material(
    type: MaterialType.transparency,
    child: RadioGroup<String>(
      groupValue: groupValue,
      onChanged: onChanged ?? (_) {},
      child: Column(
        children: items.map((item) {
          return RadioListTile<String>(
            title: Text(item.label),
            subtitle: item.subtitle == null ? null : Text(item.subtitle!),
            value: item.value,
            enabled: item.enabled ?? source.v<bool>(<Object>['enabled']),
            toggleable: source.v<bool>(<Object>['toggleable']) ?? false,
            activeColor: rfw.ArgumentDecoders.color(source, <Object>[
              'activeColor',
            ]),
            hoverColor: rfw.ArgumentDecoders.color(source, <Object>[
              'hoverColor',
            ]),
            splashRadius: _double(source, <Object>['splashRadius']),
            materialTapTargetSize:
                rfw.ArgumentDecoders.enumValue<MaterialTapTargetSize>(
                  MaterialTapTargetSize.values,
                  source,
                  <Object>['materialTapTargetSize'],
                ),
            dense: source.v<bool>(<Object>['dense']),
            selected: source.v<bool>(<Object>['selected']) ?? false,
            controlAffinity:
                rfw.ArgumentDecoders.enumValue<ListTileControlAffinity>(
                  ListTileControlAffinity.values,
                  source,
                  <Object>['controlAffinity'],
                ),
            autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
            contentPadding: rfw.ArgumentDecoders.edgeInsets(source, <Object>[
              'contentPadding',
            ]),
            visualDensity: rfw.ArgumentDecoders.visualDensity(source, <Object>[
              'visualDensity',
            ]),
            enableFeedback: source.v<bool>(<Object>['enableFeedback']),
            horizontalTitleGap: _double(source, <Object>['horizontalTitleGap']),
            minVerticalPadding: _double(source, <Object>['minVerticalPadding']),
            minLeadingWidth: _double(source, <Object>['minLeadingWidth']),
            minTileHeight: _double(source, <Object>['minTileHeight']),
            radioScaleFactor:
                _double(source, <Object>['radioScaleFactor']) ?? 1.0,
          );
        }).toList(),
      ),
    ),
  );
}

Widget buildSlider(BuildContext context, rfw.DataSource source) {
  final onChanged = source.handler<ValueChanged<double>>(
    <Object>['onChanged'],
    (trigger) =>
        (double value) => trigger(<String, Object?>{'value': value}),
  );
  final onChangeStart = source.handler<ValueChanged<double>>(
    <Object>['onChangeStart'],
    (trigger) =>
        (double value) => trigger(<String, Object?>{'value': value}),
  );
  final onChangeEnd = source.handler<ValueChanged<double>>(
    <Object>['onChangeEnd'],
    (trigger) =>
        (double value) => trigger(<String, Object?>{'value': value}),
  );
  final min = _double(source, <Object>['min']) ?? 0.0;
  final max = _double(source, <Object>['max']) ?? 1.0;
  final value = (_double(source, <Object>['value']) ?? min).clamp(min, max);

  return Material(
    type: MaterialType.transparency,
    child: Slider(
      value: value,
      secondaryTrackValue: _double(source, <Object>['secondaryTrackValue']),
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: source.v<int>(<Object>['divisions']),
      label: source.v<String>(<Object>['label']),
      activeColor: rfw.ArgumentDecoders.color(source, <Object>['activeColor']),
      inactiveColor: rfw.ArgumentDecoders.color(source, <Object>[
        'inactiveColor',
      ]),
      secondaryActiveColor: rfw.ArgumentDecoders.color(source, <Object>[
        'secondaryActiveColor',
      ]),
      thumbColor: rfw.ArgumentDecoders.color(source, <Object>['thumbColor']),
      autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
      padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
    ),
  );
}

double? _double(rfw.DataSource source, List<Object> key) {
  return source.v<double>(key) ?? source.v<int>(key)?.toDouble();
}

class _RadioGroupItem {
  const _RadioGroupItem({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.enabled,
  });

  final String value;
  final String label;
  final String? subtitle;
  final bool? enabled;
}
