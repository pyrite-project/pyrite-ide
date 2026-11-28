/// Shared building blocks for every right-click menu in the app.
///
/// A menu is three things: a surface (radius, elevation, color), a row (icon,
/// label, shortcut hint) and the code that puts it on screen. All three live
/// here so the menus cannot drift apart:
///
/// * **One radius.** [PyriteMenuSurface] takes its corners from
///   `context.outerCorners`, the same value the editor's menu uses, so a menu
///   always matches the panel language around it.
/// * **One row.** [PyriteMenuRow] owns the metrics (padding, icon box, gap to
///   the shortcut) and the highlight color, so every menu has the same rhythm.
/// * **One open path.** [showPyriteMenu] replaces `showMenu` for the surfaces
///   that drive their menu from a pointer callback (the terminal family:
///   terminal, REPL transcript, output log).
///
/// [showPyriteMenu] deliberately differs from `showMenu` in two ways:
///
/// 1. **No transition.** A context menu that fades or scales in reads as lag on
///    a right click: the pointer has not moved, so the menu should already be
///    there. Both transition durations are zero.
/// 2. **No focus steal.** `showMenu` pushes a route that takes focus, and a
///    [SelectableRegion] clears its selection as soon as it loses focus. That
///    is why right-clicking selected text used to drop the selection. This
///    route passes `requestFocus: false` and blocks the keyboard itself while
///    it is open, which keeps the surface behind it inert without moving focus.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pyrite_ide/core/constants/corner_radius.dart';
import 'package:pyrite_ide/core/constants/selection.dart';

/// One pickable row of a [showPyriteMenu] popup.
@immutable
class PyriteMenuEntry<T> {
  const PyriteMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.shortcut = '',
    this.enabled = true,
    this.destructive = false,
    this.dividerBefore = false,
  });

  /// Reported back by [showPyriteMenu] when the row is picked.
  final T value;

  final String label;
  final IconData? icon;

  /// Shortcut hint shown at the trailing edge, e.g. `Cmd+C`.
  final String shortcut;

  /// A disabled row stays visible — a menu whose row count changes under the
  /// pointer moves its own items — but cannot be picked.
  final bool enabled;

  /// Renders the row in the error color for an action that destroys data.
  final bool destructive;

  /// Draws a separator above this row, grouping it away from the rows before.
  final bool dividerBefore;
}

/// Puts a menu at [globalPosition] and reports the picked [PyriteMenuEntry].
///
/// Resolves to null when the menu is dismissed without a pick.
Future<T?> showPyriteMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<PyriteMenuEntry<T>> entries,
  double minWidth = 200,
  double maxWidth = 280,
  bool? isTouch,
}) {
  assert(entries.isNotEmpty, 'A menu needs at least one row.');
  // The overlay's coordinate space is the app window; the menu is anchored at
  // the pointer with the same point as both ends of the rectangle, so it grows
  // down-right from the click and is clamped back inside the window.
  final overlay = Overlay.of(context).context.findRenderObject();
  final size = overlay is RenderBox ? overlay.size : MediaQuery.sizeOf(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _PyriteMenuRoute<T>(
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & size,
      ),
      entries: entries,
      minWidth: minWidth,
      maxWidth: maxWidth,
      isTouch: isTouch ?? usesTouchMenuMetrics,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Default for [showPyriteMenu]'s `isTouch`: touch platforms get the larger hit
/// targets and drop the shortcut hint, exactly like the editor menu does on
/// mobile. Callers that already know their own input mode can override it.
bool get usesTouchMenuMetrics => switch (defaultTargetPlatform) {
  TargetPlatform.android ||
  TargetPlatform.iOS ||
  TargetPlatform.fuchsia => true,
  _ => false,
};

class _PyriteMenuRoute<T> extends PopupRoute<T> {
  _PyriteMenuRoute({
    required this.position,
    required this.entries,
    required this.minWidth,
    required this.maxWidth,
    required this.isTouch,
    required this.barrierLabel,
  }) : super(
         // The menu is a popup over a surface the user is working in, not a
         // navigation step: taking focus would clear the very selection the
         // menu acts on.
         requestFocus: false,
       );

  final RelativeRect position;
  final List<PyriteMenuEntry<T>> entries;
  final double minWidth;
  final double maxWidth;
  final bool isTouch;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  /// A menu never dims the surface behind it: the user needs to see what they
  /// are acting on.
  @override
  Color? get barrierColor => null;

  /// Instant, both ways. See the library docs.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  void install() {
    super.install();
    // Focus stays where it was, so nothing else would stop keystrokes from
    // reaching the terminal or the editor behind the menu. Swallowing them
    // here keeps the popup modal without moving focus.
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Escape closes the menu, the same key the system menu would answer to.
    // Only pop while this route is the top one, so the key can never dismiss
    // whatever happens to be on screen after it.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        isCurrent) {
      navigator?.pop();
    }
    return true;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _PyriteMenuLayout(position),
      child: PyriteMenuSurface(
        minWidth: minWidth,
        maxWidth: maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries) ...[
              if (entry.dividerBefore) const PyriteMenuDivider(),
              PyriteMenuRow(
                label: entry.label,
                icon: entry.icon,
                shortcut: entry.shortcut,
                enabled: entry.enabled,
                destructive: entry.destructive,
                isTouch: isTouch,
                onTap: () => navigator?.pop(entry.value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Places the menu at the pointer and keeps it inside the window.
///
/// Clamping rather than flipping is what desktop menus do: the menu always
/// grows from the click towards the free space, and a click near the bottom
/// edge simply slides the whole menu up instead of opening it upwards.
class _PyriteMenuLayout extends SingleChildLayoutDelegate {
  _PyriteMenuLayout(this.position);

  final RelativeRect position;

  static const double _screenPadding = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double maxX = math.max(
      _screenPadding,
      size.width - childSize.width - _screenPadding,
    );
    final double maxY = math.max(
      _screenPadding,
      size.height - childSize.height - _screenPadding,
    );
    return Offset(
      position.left.clamp(_screenPadding, maxX),
      position.top.clamp(_screenPadding, maxY),
    );
  }

  @override
  bool shouldRelayout(_PyriteMenuLayout oldDelegate) =>
      position != oldDelegate.position;
}

/// The menu panel: one rounded, elevated surface every menu in the app shares.
///
/// Rows are laid out edge to edge, so the first and last row are clipped by
/// the surface's own corner radius instead of showing a square highlight
/// inside a rounded panel.
class PyriteMenuSurface extends StatelessWidget {
  const PyriteMenuSurface({
    super.key,
    required this.child,
    this.minWidth = 200,
    this.maxWidth = 280,
    this.maxHeight,
  });

  final Widget child;
  final double minWidth;
  final double maxWidth;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: context.outerCorners,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? double.infinity,
        ),
        child: child,
      ),
    );
  }
}

/// One row of a menu: optional icon, label, optional shortcut hint.
///
/// The highlight is the app-wide "selected row" color, so a hovered menu item
/// reads the same as a selected tree node.
class PyriteMenuRow extends StatefulWidget {
  const PyriteMenuRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.shortcut = '',
    this.enabled = true,
    this.destructive = false,
    this.isTouch = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final String shortcut;
  final bool enabled;
  final bool destructive;
  final bool isTouch;

  @override
  State<PyriteMenuRow> createState() => _PyriteMenuRowState();
}

class _PyriteMenuRowState extends State<PyriteMenuRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = _hovered && widget.enabled;
    final foreground = !widget.enabled
        ? scheme.onSurface.withAlpha(97)
        : widget.destructive
        ? scheme.error
        : highlighted
        ? AppSelection.onItem(scheme)
        : scheme.onSurface;
    final shortcutColor = widget.enabled
        ? scheme.onSurfaceVariant
        : scheme.onSurface.withAlpha(97);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          hoverColor: AppSelection.item(scheme),
          highlightColor: AppSelection.item(scheme),
          // A ripple belongs to a button, not to a menu row that appears under
          // a stationary pointer.
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.isTouch ? 16 : 12,
              vertical: widget.isTouch ? 12 : 9,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: widget.icon == null
                      ? null
                      : Icon(
                          widget.icon,
                          size: widget.isTouch ? 20 : 16,
                          color: foreground,
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground),
                  ),
                ),
                if (!widget.isTouch && widget.shortcut.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  Text(
                    widget.shortcut,
                    style: TextStyle(fontSize: 11, color: shortcutColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separates groups of rows inside a [PyriteMenuSurface].
class PyriteMenuDivider extends StatelessWidget {
  const PyriteMenuDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1);
}
