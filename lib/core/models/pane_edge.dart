import 'package:flutter/widgets.dart';

/// One edge of a pane: where a split places the new editor group, or where
/// the console panel docks.
enum PaneEdge {
  left,
  top,
  right,
  bottom;

  /// The axis a pane is divided along to put something at this edge.
  Axis get axis => switch (this) {
    PaneEdge.left || PaneEdge.right => Axis.horizontal,
    PaneEdge.top || PaneEdge.bottom => Axis.vertical,
  };

  /// Whether what goes to this edge is laid out before the pane it divides.
  bool get isLeading => switch (this) {
    PaneEdge.left || PaneEdge.top => true,
    PaneEdge.right || PaneEdge.bottom => false,
  };
}
