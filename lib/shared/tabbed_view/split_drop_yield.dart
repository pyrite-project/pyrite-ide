import 'package:flutter/widgets.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// What a group's tab strip asks about the split-drop region around it.
///
/// The strip row covers exactly where the editor area's top band is, and a
/// drop region wins over its ancestors -- without this hook the strip
/// swallows every drop there, and the area-level top split (the gesture the
/// area edge band exists to provide) has no target at all.
abstract interface class SplitDropYield {
  /// Whether the drop of the tab drag [session] at [globalPosition], now over
  /// the enclosing group's strip, belongs to the area-level split gesture.
  ///
  /// True means the strip must stand down -- return none, show no insertion
  /// indicator -- and let the enclosing region's own bands resolve the drop.
  bool yieldsStripDrop(DropSession session, Offset globalPosition);
}

/// Hands the enclosing split-drop region to the tab strip inside it.
///
/// Implemented by `EditorSplitDropRegion`; looked up by the native tab strip
/// while a drag moves over it.
class SplitDropScope extends InheritedWidget {
  const SplitDropScope({super.key, required this.area, required super.child});

  final SplitDropYield area;

  static SplitDropYield? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SplitDropScope>()?.area;

  @override
  bool updateShouldNotify(SplitDropScope oldWidget) =>
      !identical(area, oldWidget.area);
}
