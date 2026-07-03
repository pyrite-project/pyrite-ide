# 插件类型与生命周期

PyriteIDE SDK 使用明确的插件基类区分插件职责。

```python
from pyrite_sdk.core.plugin import BasePlugin, UiPlugin, ServicePlugin, DataPlugin
```

## BasePlugin

所有插件基类。提供：

- `bridge`
- `path`
- `settings`
- `message`
- 基础生命周期钩子：`on_pause`、`on_resume`、`on_refresh`、`on_dispose`

一般不直接继承 `BasePlugin`，而是继承更具体的类型。

## UiPlugin

用于有页面和交互的插件。

```python
class MyPlugin(UiPlugin):
    def on_start(self):
        ...
```

能力：

- `pages`
- `file`
- `board`
- `editor`
- `router`
- `persistence`
- `theme`
- `i18n`
- `stubs`
- `serial`

生命周期：

- `on_start()`：插件启动时调用。
- `on_pause()`：页面离开或插件暂停时调用。
- `on_resume()`：页面恢复时调用。
- `on_refresh()`：IDE 请求页面刷新时调用。
- `on_dispose()`：插件停止或释放时调用。

## ServicePlugin

用于后台服务、设备监听、语言服务代理、同步任务等。

```python
class MyService(ServicePlugin):
    def on_start(self):
        ...
```

能力：

- `file`
- `board`
- `persistence`
- `settings`
- `theme`
- `i18n`
- `stubs`
- `serial`

Service 插件可以由用户启动/停止。多个插件启动会由 IDE 串行执行，避免多个插件同时运行 Python runtime boot 过程。

## DataPlugin

用于只贡献数据的插件。

```python
class MyData(DataPlugin):
    def on_contribute(self):
        ...

plugin = MyData()
plugin.run_once()
```

能力：

- `path`
- `settings`
- `message`
- `theme`
- `i18n`
- `stubs`

生命周期：

1. IDE 安装或启用插件。
2. IDE 运行插件一次。
3. 插件执行 `on_contribute()`。
4. 插件通过 contribute API 提交数据。
5. SDK 等待挂起请求完成后退出进程。
6. IDE 持久化 Contribution。

Data 插件不会常驻，也不显示启动/停止按钮。

## 启动顺序

IDE 对插件启动做串行化处理。即使用户短时间连续启动多个插件，IDE 也会按顺序执行每个插件启动流程，避免 Python runtime boot 和路径设置并发冲突。
