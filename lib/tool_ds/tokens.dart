import 'package:flutter/material.dart';

@immutable
class ToolColorTokens {
  const ToolColorTokens({
    required this.canvas,
    required this.panel,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.focusRing,
    required this.selection,
    required this.selectionText,
    required this.hover,
    required this.diagnosticError,
    required this.diagnosticWarning,
    required this.diagnosticInfo,
  });

  final Color canvas;
  final Color panel;
  final Color border;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  final Color accent;
  final Color accentText;
  final Color focusRing;

  final Color selection;
  final Color selectionText;
  final Color hover;

  final Color diagnosticError;
  final Color diagnosticWarning;
  final Color diagnosticInfo;

  ToolColorTokens lerp(ToolColorTokens other, double t) {
    return ToolColorTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      selectionText: Color.lerp(selectionText, other.selectionText, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      diagnosticError: Color.lerp(diagnosticError, other.diagnosticError, t)!,
      diagnosticWarning: Color.lerp(
        diagnosticWarning,
        other.diagnosticWarning,
        t,
      )!,
      diagnosticInfo: Color.lerp(diagnosticInfo, other.diagnosticInfo, t)!,
    );
  }
}

@immutable
class ToolRadiusTokens {
  const ToolRadiusTokens({
    required this.sm,
    required this.md,
    required this.lg,
  });

  final double sm;
  final double md;
  final double lg;
}

@immutable
class ToolSpacingTokens {
  const ToolSpacingTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
}

@immutable
class ToolTypographyTokens {
  const ToolTypographyTokens({
    required this.ui,
    required this.uiDense,
    required this.mono,
    required this.monoDense,
  });

  final TextStyle ui;
  final TextStyle uiDense;
  final TextStyle mono;
  final TextStyle monoDense;
}

@immutable
class ToolTokens {
  const ToolTokens({
    required this.colors,
    required this.radii,
    required this.space,
    required this.type,
  });

  final ToolColorTokens colors;
  final ToolRadiusTokens radii;
  final ToolSpacingTokens space;
  final ToolTypographyTokens type;

  static ToolTokens light({String? uiFontFamily, String? monoFontFamily}) {
    final uiFamily = uiFontFamily;
    final monoFamily = monoFontFamily;
    return ToolTokens(
      colors: const ToolColorTokens(
        canvas: Color(0xFFF7F7F8),
        panel: Color(0xFFFFFFFF),
        border: Color(0xFFD6D6DA),
        text: Color(0xFF121316),
        textMuted: Color(0xFF3A3C43),
        textFaint: Color(0xFF6B6E78),
        accent: Color(0xFF2B5BD7),
        accentText: Color(0xFFFFFFFF),
        focusRing: Color(0xFF2B5BD7),
        selection: Color(0xFF2B5BD7),
        selectionText: Color(0xFFFFFFFF),
        hover: Color(0x0A000000),
        diagnosticError: Color(0xFFD43C2F),
        diagnosticWarning: Color(0xFFB87900),
        diagnosticInfo: Color(0xFF2B5BD7),
      ),
      radii: const ToolRadiusTokens(sm: 2, md: 4, lg: 6),
      space: const ToolSpacingTokens(xs: 4, sm: 8, md: 12, lg: 16),
      type: ToolTypographyTokens(
        ui: TextStyle(
          fontSize: 12.5,
          height: 1.15,
          fontFamily: uiFamily,
          color: const Color(0xFF121316),
        ),
        uiDense: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontFamily: uiFamily,
          color: const Color(0xFF121316),
        ),
        mono: TextStyle(
          fontSize: 12.5,
          height: 1.15,
          fontFamily: monoFamily,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: const Color(0xFF121316),
        ),
        monoDense: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontFamily: monoFamily,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: const Color(0xFF121316),
        ),
      ),
    );
  }

  static ToolTokens dark({String? uiFontFamily, String? monoFontFamily}) {
    final uiFamily = uiFontFamily;
    final monoFamily = monoFontFamily;
    return ToolTokens(
      colors: const ToolColorTokens(
        canvas: Color(0xFF0F1012),
        panel: Color(0xFF15161A),
        border: Color(0xFF2A2C33),
        text: Color(0xFFE7E8EC),
        textMuted: Color(0xFFC2C4CD),
        textFaint: Color(0xFF8B8E99),
        accent: Color(0xFF5C85FF),
        accentText: Color(0xFF0B0C0F),
        focusRing: Color(0xFF5C85FF),
        selection: Color(0xFF2C4DBD),
        selectionText: Color(0xFFE7E8EC),
        hover: Color(0x14FFFFFF),
        diagnosticError: Color(0xFFFF5B4D),
        diagnosticWarning: Color(0xFFFFB020),
        diagnosticInfo: Color(0xFF5C85FF),
      ),
      radii: const ToolRadiusTokens(sm: 2, md: 4, lg: 6),
      space: const ToolSpacingTokens(xs: 4, sm: 8, md: 12, lg: 16),
      type: ToolTypographyTokens(
        ui: TextStyle(
          fontSize: 12.5,
          height: 1.15,
          fontFamily: uiFamily,
          color: const Color(0xFFE7E8EC),
        ),
        uiDense: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontFamily: uiFamily,
          color: const Color(0xFFE7E8EC),
        ),
        mono: TextStyle(
          fontSize: 12.5,
          height: 1.15,
          fontFamily: monoFamily,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: const Color(0xFFE7E8EC),
        ),
        monoDense: TextStyle(
          fontSize: 12,
          height: 1.1,
          fontFamily: monoFamily,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: const Color(0xFFE7E8EC),
        ),
      ),
    );
  }
}
