# 快速开始

本章创建一个最小 Data 插件和一个最小 UI 插件。Data 插件适合主题、语言包、stubs 等数据包；UI 插件适合需要页面和交互的插件。

## 最小目录结构

```text
my_plugin/
  __main__.py
  plugin.toml
  requirements.txt
```

`plugin.toml` 是插件清单，`__main__.py` 是 Python 入口。

## 最小 Data 插件

Data 插件运行一次，完成贡献后退出。它不会长期占用插件进程，也不会显示启动/停止按钮。

```python
from pyrite_sdk.core.plugin import DataPlugin


class MyDataPlugin(DataPlugin):
    def on_contribute(self):
        self.message.success("Data plugin contributed")


plugin = MyDataPlugin()
plugin.run_once()
```

清单：

```toml
[general]
name = "My Data Plugin"
id = "my-data-plugin"
version = "1.0.0"
author = "Me"
type = "data"

[permissions]
data = true

[platform]
linux = true
macos = true
windows = true
android = true
```

## 最小 UI 插件

UI 插件继承 `UiPlugin`，需要实现 `on_start()`，并创建页面。

```python
from pyrite_sdk.core.plugin import UiPlugin
from pyrite_sdk.api.ui.page import Page
from pyrite_sdk.api.ui.widgets import Text, Scaffold
from pyrite_sdk.models.consts import Package, Ui
from pyrite_sdk.api.ui.widgets import NewWidget


class MyUiPlugin(UiPlugin):
    def on_start(self):
        page = Page(packages=[Package.core.widgets, Package.core.material])
        root = NewWidget(Ui.root).add_to(page)
        with Scaffold().add_to(root):
            Text("Hello from plugin")
        self.pages["main"] = page


plugin = MyUiPlugin()
plugin.start()
```

清单：

```toml
[general]
name = "My UI Plugin"
id = "my-ui-plugin"
version = "1.0.0"
author = "Me"
type = "ui"

[permissions]
ui = true

[platform]
linux = true
macos = true
windows = true
android = true
```

## requirements.txt

开发时通常依赖本地 SDK wheel：

```text
pyrite-sdk @ file:///E:/Can1425/pyrite-sdk/dist/pyrite_sdk-0.0.0-py3-none-any.whl
```

实际路径以你构建出的 wheel 为准。

## 打包

在插件目录执行：

```powershell
$env:PYTHONIOENCODING='utf-8'; $env:PYTHONUTF8='1'; pyrsdk . -p Windows -r '-rrequirements.txt'
```

输出产物：

```text
build/app.zip
build/app.zip.hash
```
