/// Default Python runtime hooks for [PythonRuntimeHost].
///
/// Native builds run CPython through `serious_python`; the web build resolves
/// the default export, which reports the runtime as unavailable so the app
/// boots normally with plugins disabled.
export 'python_runtime_defaults_web.dart'
    if (dart.library.io) 'python_runtime_defaults_io.dart';
