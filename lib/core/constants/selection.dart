import 'package:flutter/material.dart';

/// Single source of truth for every "this is selected" tint in the app.
///
/// Two different things can read as selected, and they are deliberately not
/// the same color:
///
/// * a **text selection** tints the background behind glyphs, so it has to
///   stay translucent — the syntax colors underneath must survive it. That is
///   [text].
/// * a **selected row** (menu item, tree node, list tile, tab) fills a whole
///   container and carries its own foreground, so it uses a container role.
///   That is [item].
///
/// Both are derived from the [ColorScheme] rather than a fixed palette, so a
/// plugin theme or a different seed color repaints every selection in the app
/// consistently, and there is exactly one place to change if the tint needs to
/// be stronger or weaker.
abstract final class AppSelection {
  /// Opacity of the text-selection tint over the surface it highlights.
  ///
  /// Low enough that the text stays readable through it on both light and dark
  /// surfaces, high enough to separate from a plain background. Tuned against
  /// the darkest editor background and the brightest terminal background.
  static const double textAlpha = 0.3;

  /// Highlight painted behind selected text.
  ///
  /// Used by the editor, the terminal family (terminal, REPL transcript, output
  /// log) and every text field, so a selection looks the same wherever it is
  /// made.
  static Color text(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: textAlpha);

  /// Fill of a selected or hovered row: menu item, tree node, list tile.
  static Color item(ColorScheme scheme) => scheme.secondaryContainer;

  /// Foreground that stays legible on top of [item].
  static Color onItem(ColorScheme scheme) => scheme.onSecondaryContainer;
}
