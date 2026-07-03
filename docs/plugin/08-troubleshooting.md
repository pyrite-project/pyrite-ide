# 排错

## ImportError: cannot import name DataPlugin

原因通常是插件包里安装了旧版 `pyrite-sdk`。

处理：

1. 在 SDK 仓库执行 `python -m build`。
2. 确认插件 `requirements.txt` 指向最新 wheel。
3. 重新执行 `pyrsdk` 打包。
4. 重新安装插件。

## Permission denied

示例：

```text
Permission denied: settings:write
```

处理：

1. 在 `plugin.toml` 中声明权限。
2. 重新打包插件。
3. 重新安装插件。

例如写设置需要：

```toml
[permissions]
settings = true
```

## Windows 路径 unicodeescape 错误

示例：

```text
SyntaxError: (unicode error) 'unicodeescape' codec can't decode bytes
```

原因是 Windows 路径中的 `\U` 被 Python 字符串解释为 Unicode 转义。

IDE 注入给插件的路径环境变量会使用 `/` 分隔符。插件代码中也建议使用 `pathlib.Path`，不要手写未转义的 Windows 字符串。

## Data 插件发送请求后连接关闭

DataPlugin 会在 `on_contribute()` 后等待 SDK 请求回包清空再退出。如果仍看到请求未完成就退出，检查：

- 是否继承 `DataPlugin`。
- 是否调用 `plugin.run_once()` 或 `plugin.start()`。
- 是否使用了最新 SDK wheel。

## settings layers 已有配置但插件没有覆盖

这是预期行为。数据插件不应覆盖用户已有配置，应提示用户并保留现有设置。

## stubs 配置没有进入 pylsp

检查：

1. Stubs 插件是否已启用。
2. 设置中 `MicroPython Stubs` 是否启用。
3. `Stubs Layers` 是否包含有效的 `provider/profile`。
4. IDE 输出中是否有 `Stubs refresh requested` 和 `Refreshing LSP stubs paths` 日志。

## 插件连续启动异常

IDE 会串行执行插件启动流程。如果仍出现异常，查看 IDE 输出中的插件启动日志，确认是否有某个插件启动阻塞或未退出。
