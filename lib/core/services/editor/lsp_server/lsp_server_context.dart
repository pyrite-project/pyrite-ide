import 'package:pyrite_ide/core/models/settings.dart';
import 'package:pyrite_ide/core/services/editor/python_virtual_environment.dart';

/// Everything a language-server adapter sees when the IDE prepares one launch.
///
/// The common `buildLspStubsConfig` pipeline resolves these once (stubs layers,
/// virtual environment, settings) and hands them to whichever adapter claims
/// the launch, so adapters never read settings providers themselves.
class LspServerContext {
  const LspServerContext({
    required this.transport,
    required this.stdioExecutable,
    required this.stdioArgs,
    required this.stubsEnabled,
    required this.stubsPaths,
    required this.pythonInterpreter,
    required this.typeCheckingMode,
    this.virtualEnvironment,
    this.workspacePath = '',
  });

  final LspType transport;

  /// Configured stdio launch. Empty for WebSocket transports.
  final String stdioExecutable;
  final String stdioArgs;

  final bool stubsEnabled;

  /// Resolved MicroPython stubs directories, in layer then extra-path order.
  final List<String> stubsPaths;

  /// Interpreter of the selected virtual environment, or '' when none.
  final String pythonInterpreter;
  final PythonVirtualEnvironment? virtualEnvironment;

  final BasedPyrightTypeCheckingMode typeCheckingMode;
  final String workspacePath;

  /// The full stdio launch command, executable first.
  ///
  /// Wrapper launches such as `python -m zuban` or `uvx zuban` identify the
  /// real server through an argument, which is why matching covers every
  /// token and not just the executable.
  List<String> get stdioCommandTokens => [
    if (stdioExecutable.trim().isNotEmpty) stdioExecutable.trim(),
    ...stdioArgs.split(_whitespace).where((token) => token.isNotEmpty),
  ];

  static final RegExp _whitespace = RegExp(r'\s+');
}
