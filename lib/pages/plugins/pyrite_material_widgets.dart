import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart' as markdown_widget;
import 'package:rfw/rfw.dart' as rfw;

rfw.LocalWidgetLibrary createPyriteMaterialWidgets() {
  return rfw.LocalWidgetLibrary(<String, rfw.LocalWidgetBuilder>{
    ...rfw.createMaterialWidgets().widgets,
    'Markdown': _buildMarkdown,
    'MarkdownWidget': _buildMarkdown,
    'MarkdownBlock': _buildMarkdownBlock,
    'TextField': _buildTextField,
    'TextFormField': _buildTextField,
  });
}

Widget _buildMarkdown(BuildContext context, rfw.DataSource source) {
  return markdown_widget.MarkdownWidget(
    data: source.v<String>(<Object>['data']) ?? '',
    selectable: source.v<bool>(<Object>['selectable']) ?? true,
    shrinkWrap: source.v<bool>(<Object>['shrinkWrap']) ?? false,
    padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
    config: _decodeMarkdownConfig(source),
  );
}

Widget _buildMarkdownBlock(BuildContext context, rfw.DataSource source) {
  final padding = rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']);
  final block = markdown_widget.MarkdownBlock(
    data: source.v<String>(<Object>['data']) ?? '',
    selectable: source.v<bool>(<Object>['selectable']) ?? true,
    config: _decodeMarkdownConfig(source),
  );

  if (padding == null) {
    return block;
  }

  return Padding(padding: padding, child: block);
}

Map<String, TextStyle> _mergeMarkdownCodeTheme(
  Map<String, TextStyle> theme,
  TextStyle style,
) {
  return theme.map(
    (String key, TextStyle value) =>
        MapEntry<String, TextStyle>(key, value.merge(style)),
  );
}

Map<String, TextStyle>? _decodeMarkdownCodeTheme(
  String? theme,
  markdown_widget.MarkdownConfig baseConfig,
) {
  switch (theme) {
    case 'dark':
      return markdown_widget.PreConfig.darkConfig.theme;
    case 'light':
      return baseConfig.pre.theme;
  }
  return null;
}

markdown_widget.MarkdownConfig? _decodeMarkdownConfig(rfw.DataSource source) {
  final onTapLink = source.handler<ValueChanged<String>>(
    <Object>['onTapLink'],
    (trigger) =>
        (String url) => trigger(<String, Object?>{'url': url}),
  );
  final baseConfig = markdown_widget.MarkdownConfig.defaultConfig;
  final configs = <markdown_widget.WidgetConfig>[];
  final codeBlockPadding = rfw.ArgumentDecoders.edgeInsets(source, <Object>[
    'codeBlockPadding',
  ]);
  final codeBlockMargin = rfw.ArgumentDecoders.edgeInsets(source, <Object>[
    'codeBlockMargin',
  ]);
  final codeBlockDecoration = rfw.ArgumentDecoders.decoration(source, <Object>[
    'codeBlockDecoration',
  ]);
  final codeBlockTextStyle = rfw.ArgumentDecoders.textStyle(source, <Object>[
    'codeBlockTextStyle',
  ]);
  final codeBlockStyleNotMatched = rfw.ArgumentDecoders.textStyle(
    source,
    <Object>['codeBlockStyleNotMatched'],
  );
  final codeBlockLanguage = source.v<String>(<Object>['codeBlockLanguage']);
  final codeBlockTheme = _decodeMarkdownCodeTheme(
    source.v<String>(<Object>['codeBlockTheme']),
    baseConfig,
  );
  final inlineCodeTextStyle = rfw.ArgumentDecoders.textStyle(source, <Object>[
    'inlineCodeTextStyle',
  ]);

  if (codeBlockPadding != null ||
      codeBlockMargin != null ||
      codeBlockDecoration != null ||
      codeBlockTextStyle != null ||
      codeBlockStyleNotMatched != null ||
      codeBlockLanguage != null ||
      codeBlockTheme != null) {
    final effectiveCodeTheme = codeBlockTheme ?? baseConfig.pre.theme;
    final styleNotMatched =
        (baseConfig.pre.styleNotMatched ?? const TextStyle())
            .merge(codeBlockTextStyle)
            .merge(codeBlockStyleNotMatched);
    configs.add(
      baseConfig.pre.copy(
        padding: codeBlockPadding,
        margin: codeBlockMargin,
        decoration: codeBlockDecoration,
        textStyle: codeBlockTextStyle == null
            ? null
            : baseConfig.pre.textStyle.merge(codeBlockTextStyle),
        styleNotMatched:
            (codeBlockTextStyle == null && codeBlockStyleNotMatched == null)
            ? null
            : styleNotMatched,
        theme: codeBlockTextStyle == null
            ? codeBlockTheme
            : _mergeMarkdownCodeTheme(effectiveCodeTheme, codeBlockTextStyle),
        language: codeBlockLanguage,
      ),
    );
  }

  if (inlineCodeTextStyle != null) {
    configs.add(
      markdown_widget.CodeConfig(
        style: baseConfig.code.style.merge(inlineCodeTextStyle),
      ),
    );
  }

  if (onTapLink != null) {
    configs.add(markdown_widget.LinkConfig(onTap: onTapLink));
  }

  if (configs.isEmpty) {
    return null;
  }

  return baseConfig.copy(configs: configs);
}

Widget _buildTextField(BuildContext context, rfw.DataSource source) {
  final onChanged = source.handler<ValueChanged<String>>(
    <Object>['onChanged'],
    (trigger) =>
        (String value) => trigger(<String, Object?>{'value': value}),
  );
  final onSubmitted = source.handler<ValueChanged<String>>(
    <Object>['onSubmitted'],
    (trigger) =>
        (String value) => trigger(<String, Object?>{'value': value}),
  );

  return _PyriteTextField(
    value: source.v<String>(<Object>['value']),
    initialValue: source.v<String>(<Object>['initialValue']),
    decoration: _decodeInputDecoration(source),
    keyboardType: _decodeKeyboardType(
      source.v<String>(<Object>['keyboardType']),
    ),
    textInputAction: _decodeTextInputAction(
      source.v<String>(<Object>['textInputAction']),
    ),
    style: rfw.ArgumentDecoders.textStyle(source, <Object>['style']),
    textAlign:
        rfw.ArgumentDecoders.enumValue<TextAlign>(
          TextAlign.values,
          source,
          <Object>['textAlign'],
        ) ??
        TextAlign.start,
    textDirection: rfw.ArgumentDecoders.enumValue<TextDirection>(
      TextDirection.values,
      source,
      <Object>['textDirection'],
    ),
    autofocus: source.v<bool>(<Object>['autofocus']) ?? false,
    obscureText: source.v<bool>(<Object>['obscureText']) ?? false,
    autocorrect: source.v<bool>(<Object>['autocorrect']) ?? true,
    maxLines: source.v<int>(<Object>['maxLines']),
    minLines: source.v<int>(<Object>['minLines']),
    maxLength: source.v<int>(<Object>['maxLength']),
    enabled: source.v<bool>(<Object>['enabled']),
    readOnly: source.v<bool>(<Object>['readOnly']) ?? false,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    onTap: source.voidHandler(<Object>['onTap']),
  );
}

InputDecoration _decodeInputDecoration(rfw.DataSource source) {
  return InputDecoration(
    labelText:
        source.v<String>(<Object>['decoration', 'labelText']) ??
        source.v<String>(<Object>['labelText']),
    hintText:
        source.v<String>(<Object>['decoration', 'hintText']) ??
        source.v<String>(<Object>['hintText']),
    helperText: source.v<String>(<Object>['decoration', 'helperText']),
    errorText: source.v<String>(<Object>['decoration', 'errorText']),
    prefixText: source.v<String>(<Object>['decoration', 'prefixText']),
    suffixText: source.v<String>(<Object>['decoration', 'suffixText']),
    prefixIcon: source.optionalChild(<Object>['decoration', 'prefixIcon']),
    suffixIcon: source.optionalChild(<Object>['decoration', 'suffixIcon']),
    isDense: source.v<bool>(<Object>['decoration', 'isDense']) ?? true,
    border: const OutlineInputBorder(),
  );
}

TextInputType? _decodeKeyboardType(String? value) {
  return switch (value) {
    'datetime' => TextInputType.datetime,
    'emailAddress' => TextInputType.emailAddress,
    'multiline' => TextInputType.multiline,
    'name' => TextInputType.name,
    'none' => TextInputType.none,
    'number' => TextInputType.number,
    'phone' => TextInputType.phone,
    'streetAddress' => TextInputType.streetAddress,
    'text' => TextInputType.text,
    'url' => TextInputType.url,
    'visiblePassword' => TextInputType.visiblePassword,
    _ => null,
  };
}

TextInputAction? _decodeTextInputAction(String? value) {
  return switch (value) {
    'continueAction' => TextInputAction.continueAction,
    'done' => TextInputAction.done,
    'emergencyCall' => TextInputAction.emergencyCall,
    'go' => TextInputAction.go,
    'join' => TextInputAction.join,
    'newline' => TextInputAction.newline,
    'next' => TextInputAction.next,
    'none' => TextInputAction.none,
    'previous' => TextInputAction.previous,
    'route' => TextInputAction.route,
    'search' => TextInputAction.search,
    'send' => TextInputAction.send,
    'unspecified' => TextInputAction.unspecified,
    _ => null,
  };
}

class _PyriteTextField extends StatefulWidget {
  const _PyriteTextField({
    required this.value,
    required this.initialValue,
    required this.decoration,
    required this.keyboardType,
    required this.textInputAction,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.autofocus,
    required this.obscureText,
    required this.autocorrect,
    required this.maxLines,
    required this.minLines,
    required this.maxLength,
    required this.enabled,
    required this.readOnly,
    required this.onChanged,
    required this.onSubmitted,
    required this.onTap,
  });

  final String? value;
  final String? initialValue;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool autofocus;
  final bool obscureText;
  final bool autocorrect;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool? enabled;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  @override
  State<_PyriteTextField> createState() => _PyriteTextFieldState();
}

class _PyriteTextFieldState extends State<_PyriteTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value ?? widget.initialValue ?? '',
    );
  }

  @override
  void didUpdateWidget(_PyriteTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value;
    if (value != null && value != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: TextField(
        controller: _controller,
        decoration: widget.decoration,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        style: widget.style,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
      ),
    );
  }
}
