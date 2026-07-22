import 'package:markdown_widget/markdown_widget.dart' as markdown_widget;
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart' as rfw;

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

Widget buildMarkdown(BuildContext context, rfw.DataSource source) {
  return markdown_widget.MarkdownWidget(
    data: source.v<String>(<Object>['data']) ?? '',
    selectable: source.v<bool>(<Object>['selectable']) ?? true,
    shrinkWrap: source.v<bool>(<Object>['shrinkWrap']) ?? false,
    padding: rfw.ArgumentDecoders.edgeInsets(source, <Object>['padding']),
    config: _decodeMarkdownConfig(source),
  );
}

Widget buildMarkdownBlock(BuildContext context, rfw.DataSource source) {
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
