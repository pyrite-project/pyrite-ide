import 'package:code_forge/code_forge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/editor/editor_controller_provider.dart';

/// Diagnostics for one open file, as rendered by the Problems panel.
class FileProblems {
  const FileProblems({required this.path, required this.diagnostics});

  final String path;
  final List<LspErrors> diagnostics;

  int get errorCount =>
      diagnostics.where((diagnostic) => diagnostic.severity == 1).length;

  int get warningCount =>
      diagnostics.where((diagnostic) => diagnostic.severity == 2).length;
}

/// Workspace-wide diagnostic aggregation for the Problems panel.
///
/// The language server publishes diagnostics per document onto each open
/// editor's [CodeForgeController.diagnosticsNotifier]; the panel needs one
/// list across every open file. This notifier mirrors the controller map:
/// whenever a tab opens, a subscription attaches to its diagnostics notifier,
/// and closing the tab detaches it and drops the entry. Language servers also
/// publish diagnostics for files nobody opened (references across the
/// workspace); those stay invisible here because there is no editor to attach
/// to — the panel deliberately only reports files the user has open.
class ProblemsNotifier extends StateNotifier<List<FileProblems>> {
  ProblemsNotifier(this._ref) : super(const []) {
    _ref.listen(
      editorControllerMapProvider,
      (_, next) => _syncControllers(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final Map<String, VoidCallback> _detach = {};

  void _syncControllers(Map<String, CodeForgeController> controllers) {
    for (final path in List<String>.of(_detach.keys)) {
      if (!controllers.containsKey(path)) {
        _detach.remove(path)!();
        state = [
          for (final entry in state)
            if (entry.path != path) entry,
        ];
      }
    }
    for (final entry in controllers.entries) {
      if (_detach.containsKey(entry.key)) continue;
      final path = entry.key;
      final controller = entry.value;
      void listener() => _updateFile(path);
      controller.diagnosticsNotifier.addListener(listener);
      _detach[path] = () =>
          controller.diagnosticsNotifier.removeListener(listener);
      _updateFile(path);
    }
  }

  void _updateFile(String path) {
    if (!mounted) return;
    final controller = _ref.read(editorControllerMapProvider)[path];
    if (controller == null) return;
    final diagnostics = controller.diagnosticsNotifier.value;
    state = [
      for (final entry in state)
        if (entry.path != path) entry,
      FileProblems(path: path, diagnostics: diagnostics),
    ];
  }
}

final problemsProvider =
    StateNotifierProvider<ProblemsNotifier, List<FileProblems>>((ref) {
      return ProblemsNotifier(ref);
    });

/// Error and warning totals for one file, as shown on its tab.
///
/// A record rather than a class so that Riverpod's change check sees value
/// equality: diagnostics for one file come and go constantly while the user
/// types, and a tab must only rebuild when its own counts actually moved.
typedef TabProblemCounts = ({int errors, int warnings});

/// Picks [path]'s counts out of the workspace-wide list.
///
/// A path with no entry is not an error state — it means no file open under that
/// path has published diagnostics, which is what a clean workspace looks like.
/// Callers render it as "no badge", not as "zero problems, something wrong".
TabProblemCounts problemCountsFor(List<FileProblems> problems, String path) {
  for (final entry in problems) {
    if (entry.path == path) {
      return (errors: entry.errorCount, warnings: entry.warningCount);
    }
  }
  return (errors: 0, warnings: 0);
}

final tabProblemCountsProvider = Provider.family<TabProblemCounts, String>((
  ref,
  path,
) {
  return problemCountsFor(ref.watch(problemsProvider), path);
});

/// File paths the user collapsed in the Problems panel.
///
/// Panel-local UI state rather than something derived from diagnostics: a
/// collapsed group stays collapsed across diagnostic updates, and stale paths
/// (a closed file) are simply ignored by the view.
final collapsedProblemFilesProvider = StateProvider<Set<String>>((ref) => {});
