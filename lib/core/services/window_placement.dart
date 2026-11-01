import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/models/window_placement.dart';

/// The window's current placement, maintained by the desktop window shell.
///
/// Null until startup restores a placement (or the window shell publishes the
/// live geometry), and read by `PersistenceManager.saveFromContainer` so the
/// next session reopens where this one was left.
final StateProvider<WindowPlacement?> windowPlacementProvider =
    StateProvider<WindowPlacement?>((ref) => null);
