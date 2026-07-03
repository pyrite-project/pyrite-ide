# 打包与发布

插件使用 `pyrsdk` 打包。打包产物是 `build/app.zip`。

## 构建 SDK wheel

如果修改了 `pyrite-sdk`，先在 SDK 仓库构建 wheel：

```powershell
python -m build
```

构建产物通常位于：

```text
E:\Can1425\pyrite-sdk\dist\pyrite_sdk-0.0.0-py3-none-any.whl
```

## requirements.txt

插件目录中的 `requirements.txt` 应引用 SDK wheel 和其他依赖。

```text
pyrite-sdk @ file:///E:/Can1425/pyrite-sdk/dist/pyrite_sdk-0.0.0-py3-none-any.whl
```

如果插件需要第三方包，也写在这里。

## 打包命令

Windows：

```powershell
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONUTF8='1'; pyrsdk . -p Windows -r '-rrequirements.txt'
```

输出：

```text
build/app.zip
build/app.zip.hash
```

## 安装

在 PyriteIDE 插件页选择 `build/app.zip` 安装。

## 注意事项

- 修改 SDK 后，必须重新构建 wheel，再重新打包插件。
- 修改 `plugin.toml` 权限后，必须重新打包并重新安装插件。
- `pyrsdk` 有时会在清理临时 `.git` 目录时报 `PermissionError: [WinError 5]`。如果 `build/app.zip` 已生成，产物通常可用。
- Data 插件重新安装或重新启用后会运行一次 `on_contribute()`。
