# SDK API

本章按能力列出 Python SDK 的主要入口。具体方法以 `pyrite-sdk/src/pyrite_sdk/api` 中实现为准。

## 通用 API

所有插件都有：

```python
self.path
self.settings
self.message
```

### path

用于获取插件相关目录。

```python
self.path.plugin()
self.path.data()
self.path.cache()
self.path.temp()
```

常用目录：

- plugin：插件解包目录
- data：插件数据目录
- cache：插件缓存目录
- temp：临时目录

### message

显示 IDE 消息。

```python
self.message.info("info")
self.message.success("success")
self.message.warning("warning")
self.message.error("error")
```

IDE 会显示顶部消息，并同时写入 IDE 输出日志。

### settings

读取或写入 IDE 设置。需要 `settings` 权限。

```python
layers = self.settings.micropython_stubs.get_layers(lambda **cb: ...)
self.settings.micropython_stubs.set_layers([...])
```

常用设置项包括：

- `micropython.stubs.enabled`
- `micropython.stubs.layers`
- `micropython.stubs.extra_paths`
- `serial.default_baud_rate`
- `serial.auto_reconnect`

## UI 插件 API

`UiPlugin` 额外提供：

```python
self.pages
self.file
self.board
self.editor
self.router
self.persistence
self.serial
self.theme
self.i18n
self.stubs
```

### UI 页面

```python
from pyrite_sdk.api.ui.page import Page
from pyrite_sdk.api.ui.widgets import Text, Scaffold, NewWidget
from pyrite_sdk.models.consts import Package, Ui

page = Page(packages=[Package.core.widgets, Package.core.material])
root = NewWidget(Ui.root).add_to(page)
with Scaffold().add_to(root):
    Text("Hello")
self.pages["main"] = page
```

### file

本地项目文件操作。需要 `file` 权限。

典型能力：

- 获取项目根目录
- 读取目录
- 读取/写入文件
- 创建/删除/重命名文件或目录
- 打开文件或文件夹

### board

开发板文件操作。需要 `board` 权限。语义和 `file` 类似，但目标是连接的设备文件系统。

### editor

编辑器操作。需要 `editor` 权限。

典型能力：

- 读取当前文本
- 设置文本
- 获取光标/选择区
- 打开/关闭标签页
- 查找文本

### serial

串口操作。需要 `serial` 权限。

典型能力：

- 列出串口
- 连接/断开
- 发送文本或命令
- 获取状态
- 设置波特率和自动重连

## Service 插件 API

`ServicePlugin` 没有页面能力，但可以访问后台任务常用 API：

```python
self.file
self.board
self.persistence
self.settings
self.serial
self.theme
self.i18n
self.stubs
```

## Data 插件 API

`DataPlugin` 主要使用数据贡献 API：

```python
self.theme.contribute(...)
self.i18n.contribute(...)
self.stubs.contribute(...)
```

Data 插件可以使用 `settings` 读取或初始化 IDE 配置，但必须在 `plugin.toml` 中声明 `settings` 权限。
