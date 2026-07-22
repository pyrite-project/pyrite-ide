# 总述

本文档为技术解析文档，如果你是插件开发者或用户，你不必阅读此文档。

在阅读此文档前，我们建议你对 PyriteIDE 基础架构，PyriteIDE 插件开发，SeriousPython 有一定了解。

PyriteIDE Python Runtime 是 PyriteIDE 的重要组成部分，其平台层的源码仓库以子模块的形式嵌入了 PyriteIDE 主仓库中。它是 PyriteIDE 的跨平台的 Python 运行时，为插件系统提供跨平台的运行时。

PyriteIDE Python Runtime 的上游为 flet-dev/serious-python，基于 Flet 团队提供的方案，我们进行了一些变更，这将会在下文指出。

下文会将 PyriteIDE Python Runtime 简写为 Runtime。

本文档出现的代码解析均以 Windows 平台的实现为例。

# 架构解析

整个 Runtime 分为三层，平台层，引导层，插件层。

## 平台层

平台层为整个 Runtime 的核心实现，基于 serious-python，分平台进行了实现并最终封装为了 Flutter 包（在 PyriteIDE 中，包名为 serious-python）。我们可以单独称其为 Runtime，但在本文档中我们将其称为 Runtime 的平台层。

## 引导层

由于平台层解释器全局单例的实现，在执行插件层提供的 Python 代码时需要进行一些必要操作。它是一个普通的 serious-python 的资源文件，以一个压缩包的形式（python_runtime_boot.zip）存在于 IDE 源码仓库的 assets 中。

## 插件层

插件层严格意义上讲并不属于 Runtime，但考虑到其和 Runtime 耦合紧密且其为 Runtime 最终处理的内容的所在处，故将其作为单独一层。

# 重大变更

以 Windows 平台的 RunPythonProgram 为例：


```cpp
// 原生实现
void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath) {
    Py_Initialize();

    FILE *file;
    errno_t err = fopen_s(&file, appPath.c_str(), "r");
    if (err == 0 && file != NULL)
    {
        PyRun_SimpleFileEx(file, appPath.c_str(), 1);
        fclose(file);
    }

    Py_Finalize();
}
```

```cpp
// Runtime 实现
void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath, const EncodableMap& env_vars) {
  Log("RunPythonProgram entered for: " + appPath);
  PyGILState_STATE gstate = PyGILState_Ensure();
  Log("GIL acquired");

  // Update os.environ with provided environment variables
  if (!env_vars.empty()) {
    std::string updateScript = "import os\n";
    for (const auto& kv : env_vars) {
      const auto& key = kv.first;
      const auto& value = kv.second;
      if (auto str_key = std::get_if<std::string>(&key);
          auto str_value = std::get_if<std::string>(&value)) {
        std::string escaped_value = *str_value;
        size_t pos = 0;
        while ((pos = escaped_value.find("'", pos)) != std::string::npos) {
          escaped_value.replace(pos, 1, "\\'");
          pos += 2;
        }
        updateScript += "os.environ['" + *str_key + "'] = '" + escaped_value + "'\n";
      }
    }
    Log("Updating os.environ:\n" + updateScript);
    int ret = PyRun_SimpleString(updateScript.c_str());
    if (ret != 0) {
      Log("Failed to update os.environ");
      PyErr_Print();
    }
  }

  int ret = PyRun_SimpleString("print('Hello from inline Python')\nimport sys; sys.stdout.flush()");
  if (ret != 0) {
    Log("Inline Python test failed, code=" + std::to_string(ret));
    PyErr_Print();
  } else {
    Log("Inline Python test succeeded");
  }

  FILE* file;
  errno_t err = fopen_s(&file, appPath.c_str(), "r");
  if (err == 0 && file != nullptr) {
    Log("File opened successfully: " + appPath);
    ret = PyRun_SimpleFileEx(file, appPath.c_str(), 1);
    if (ret != 0) {
      Log("Python file execution failed with code " + std::to_string(ret));
      PyErr_Print();
    } else {
      Log("Python file executed successfully");
    }
  } else {
    Log("Failed to open Python file: " + appPath + ", errno=" + std::to_string(err));
  }

  PyGILState_Release(gstate);
  Log("GIL released, RunPythonProgram finished");
}
```

## CPython 生命周期的管理

serious-python 的原生实现是即用即走的模式，在 `PyRun_SimpleFileEx(...);` 前后直接进行 `Py_Initialize();` 和 `Py_Finalize();` 初始化和销毁 CPython，对于运行插件的需求而言几乎完全不可用。

我们将初始化和销毁 CPython 的逻辑移出了 `RunPythonProgramAsync`, `RunPythonScriptAsync`, `RunPythonProgram`, `RunPythonScript` 函数。

将初始化和检查封装进 `EnsurePythonInitialized` 管理，在 上面那些函数中调用，确保全局只初始化一次且在确保已经被初始化：

```cpp
void SeriousPythonWindowsPlugin::EnsurePythonInitialized() {
  std::lock_guard<std::mutex> lock(python_mutex_);
  if (!python_initialized_) {
    Log("Initializing Python interpreter...");
    Py_Initialize();
    if (!Py_IsInitialized()) {
      Log("ERROR: Python initialization failed!");
      return;
    }
    main_thread_state = PyEval_SaveThread();
    python_initialized_ = true;
    Log("Python initialized successfully, GIL released.");
  }
}
```

将销毁逻辑移入了 `SeriousPythonWindowsPlugin` 的析构函数中，在类的实例被销毁时销毁 CPython：

```cpp
SeriousPythonWindowsPlugin::~SeriousPythonWindowsPlugin() {
  Log("Destructor called");
  std::lock_guard<std::mutex> lock(python_mutex_);
  if (python_initialized_) {
    if (main_thread_state) {
      Log("Restoring main thread state before finalization");
      PyEval_RestoreThread(main_thread_state);
      main_thread_state = nullptr;
    }
    Log("Finalizing Python interpreter");
    Py_Finalize();
    python_initialized_ = false;
    Log("Python finalized");
  }
}
```

## 完善多线程支持和 Python GIL 管理

基于全局单例的修改，我们在异步线程中使用 `PyGILState_Ensure` 和 `PyGILState_Release`。

所有执行 Python 代码的线程（同步或异步）都必须先调用 `PyGILState_Ensure(...);` 获取 GIL，执行完毕后调用 `PyGILState_Release(...);` 释放。

```cpp
void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath, const EncodableMap& env_vars) {
  Log("RunPythonProgram entered for: " + appPath);
  PyGILState_STATE gstate = PyGILState_Ensure();
  Log("GIL acquired");

  ...

  PyGILState_Release(gstate);
  Log("GIL released, RunPythonProgram finished");
}
```

移除了原来在运行 Python 代码相关逻辑函数内部的 `Py_Initialize` 和 `Py_Finalize` 调用。已在上文提及。

另外，我们更改了环境变量的设置时机，将 PYTHONHOME、PYTHONPATH 等环境变量的设置移到 `Py_Initialize();` 之前（通过 `_putenv_s`），确保 Python 启动时能正确读取。

## 环境变量的传递

在 serious-python 的原生实现中，我们通过平台代码向操作系统传递环境变量，但是由于全局单例，但插件不是单例的设计，导致实际上在 `Py_Initialize();` 对于环境变量的修改是完全无效的，`os.environ` 不会同步操作系统的环境变量。

因此，我们在保留原有在初始化前设置环境变量（用于设置解释器需要的重要环境变量）的前提下，引入了动态修改 `os.environ` 的逻辑：

Windows 平台：

```cpp
void SeriousPythonWindowsPlugin::RunPythonProgram(std::string appPath, const EncodableMap& env_vars) {

  ...

  // Update os.environ with provided environment variables
  if (!env_vars.empty()) {
    std::string updateScript = "import os\n";
    for (const auto& kv : env_vars) {
      const auto& key = kv.first;
      const auto& value = kv.second;
      if (auto str_key = std::get_if<std::string>(&key);
          auto str_value = std::get_if<std::string>(&value)) {
        std::string escaped_value = *str_value;
        size_t pos = 0;
        while ((pos = escaped_value.find("'", pos)) != std::string::npos) {
          escaped_value.replace(pos, 1, "\\'");
          pos += 2;
        }
        updateScript += "os.environ['" + *str_key + "'] = '" + escaped_value + "'\n";
      }
    }
    Log("Updating os.environ:\n" + updateScript);
    int ret = PyRun_SimpleString(updateScript.c_str());
    if (ret != 0) {
      Log("Failed to update os.environ");
      PyErr_Print();
    }
  }

  int ret = PyRun_SimpleString("print('Hello from inline Python')\nimport sys; sys.stdout.flush()");
  if (ret != 0) {
    Log("Inline Python test failed, code=" + std::to_string(ret));
    PyErr_Print();
  } else {
    Log("Inline Python test succeeded");
  }

  ...

}
```

Android 平台：

```dart
// Update os.environ with provided environment variables
void updateEnvironmentVariables(Map<String, String>? environmentVariables) {
  if (environmentVariables != null) {
    final gstate = _cpython!.PyGILState_Ensure();
    final updateBuffer = StringBuffer();
    updateBuffer.writeln("import os");
    for (var v in environmentVariables.entries) {
      updateBuffer.writeln("os.environ['${v.key}'] = '${v.value}'");
    }
    final updateScript = updateBuffer.toString();
    spDebug("Updating os.environ:\n$updateScript");
    int ret =
        _cpython!.PyRun_SimpleString(updateScript.toNativeUtf8().cast<Char>());
    if (ret != 0) {
      spDebug("Failed to update os.environ");
      _cpython!.PyErr_Print();
    }
    _cpython!.PyGILState_Release(gstate);
    spDebug("GIL released, RunPythonProgram finished");
  }
}
```

由于解释器全局单例和在修改前后获取和释放 GIL，我们不用担心修改无效的问题。我们直接使用 CPython 实例执行由平台代码动态生成的 Python 代码，直接修改 `os.environ` 以达到传递环境变量的效果。

## 各个插件的环境与模块的管理

由于解释器全局单例的实现，各个独立的插件的运行环境会遭到不可避免的污染，其中模块的问题最为突出。

我们在 serious-python 要求提供的资源文件格式上做出修改，修改主要针对 Android 平台，表现为我们将生成的 site-packages 文件夹一并打包进资源文件中（与桌面平台一致）。

我们假设现在存在两个插件，它们各自的资源文件中拥有不同的 site-packages。我们称呼其中一个为 `pluginA`，一个为 `pluginB`。`pluginA` 和 `pluginB` 的 site-packages 中各自存在着一个同名模块 `this_is_a_test`，但是它们的实现完全不同，且 `pluginB` 完全无法使用 `pluginA` 的 `this_is_a_test` 模块。

假设我先在客户端使用 `SeriousPython.runProgram` 启动 `pluginA`（解压其资源文件，并运行其中的 `__main__.py`），再启动 `pluginB`，（接下来的行为出现的前提是已完成上文的修改）Runtime 将会抛出错误，并且你将会看到错误堆栈中出现 `pluginA` 的 site-packages 的路径。

这是因为 serious-python 的初始化是从第一次调用 `SeriousPython` 的方法开始的，此时 Runtime 将会设置环境变量并执行 `Py_Initialize();`。在 serious-python 的原生实现中，此时将会设置 PATH 并在其中包含该资源文件解压后的目录中的 site-packages。

我们在上文有所提到，虽然原生实现中确实会在每一次执行 `SeriousPython.runProgram` 的时候象征性的重新设置 PATH 环境变量，但是这无法影响 Python 的内部环境。与解决环境变量问题的思路类似，我们也通过直接修改/覆盖 `sys.path` 和 `sys.modules`以打到效果。

为了降低实现难度和平台层的复杂度，我们决定在 平台层 和 插件层 之间加入一个夹层：引导层。

上文已经提到，引导层也是一个普通的 serious-python 资源文件且不包含任何额外依赖项。其中有 `boot.py` 和 `setup_sys_path.py` 两个 Python 代码文件。

```python
# boot.py
import sys

def _save_original_snapshot():
    if not hasattr(sys, '_runtime_original_sys_path'):
        sys._runtime_original_sys_path = list(sys.path) # type: ignore
    if not hasattr(sys, '_runtime_original_modules_keys'):
        sys._runtime_original_modules_keys = set(sys.modules.keys()) # type: ignore

_save_original_snapshot()
```

客户端将会保证 `boot.py` 在应用启动时被立即运行，它将会将未经污染的 `sys.path` 和 `sys.modules` 的键值存入 `sys._runtime_original_sys_path` 和 `sys._runtime_original_modules_keys` 作为快照。

```python
# setup_sys_path.py
import os
import sys

def setup_sys_path():
    module_paths_str = os.environ.get('RUNTIME_MODULE_PATHS')
    replace = os.environ.get('RUNTIME_REPLACE_MODULE_PATHS') == '1'

    if not module_paths_str and not replace:
        return

    # 将字符串拆分为列表
    module_paths = module_paths_str.split("::") if module_paths_str else []

    if replace:
        if hasattr(sys, '_runtime_original_sys_path'):
            sys.path[:] = list(sys._runtime_original_sys_path)

        # 清除所有不在原始键集中的第三方模块
        if hasattr(sys, '_runtime_original_modules_keys'):
            original_keys = sys._runtime_original_modules_keys
            for mod in list(sys.modules.keys()):
                if mod not in original_keys:
                    del sys.modules[mod]
    # 反向迭代，顺序传入
    for path in reversed(module_paths):
        if not path:
            continue
        # 转换为绝对路径，去除末尾斜杠
        normalized = os.path.abspath(path).rstrip(os.sep)
        if normalized not in sys.path:
            sys.path.insert(0, normalized)

    # print("[serious_python] sys.path adjusted:", file=sys.stderr)
    # for p in sys.path:
    #     print("  ", p, file=sys.stderr)

setup_sys_path()
```

客户端将会保证 `setup_sys_path.py` 在每一次启动插件前运行：

```dart
// lib/core/sdk/plugin_run_manager_provider.dart
await SeriousPython.runAsset(
    "assets/python_runtime_boot.zip",
    appFileName: "setup_sys_path.py",
    environmentVariables: {
    "RUNTIME_MODULE_PATHS": runtimeModulePaths,
    "RUNTIME_REPLACE_MODULE_PATHS": "1",
    },
);
SeriousPython.runProgram(
    path.join(target.path, "__main__.py"),
    script: Platform.isWindows ? "" : null,
    environmentVariables: {"PYRITE_IDE_PLUGIN_PORT": "$port"},
);
```

`setup_sys_path.py` 将会依据快照重置环境。
