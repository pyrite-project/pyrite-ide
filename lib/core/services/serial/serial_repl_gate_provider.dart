import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pauses user-facing REPL input/output while a protocol transaction owns the
/// serial stream.
final serialReplIoPausedProvider = StateProvider<bool>((ref) => false);
