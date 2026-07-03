# 数据贡献 Contribution

Contribution 是插件向 IDE 提交的长期数据。它不依赖插件进程常驻。

## Contribution 与 Runtime Registration

Contribution：

- IDE 持久化记录。
- 插件进程退出后仍可使用。
- App 重启后可恢复。
- 插件禁用时停用。
- 插件卸载时删除。

Runtime Registration：

- 只在插件进程运行期间有效。
- 插件停止后清理。
- 不写入长期存储。

## theme

```python
self.theme.contribute(
    theme_id="my-theme",
    name="My Theme",
    data={...},
)
```

运行时注册：

```python
self.theme.register_runtime(...)
```

撤销：

```python
self.theme.revoke("my-theme")
```

## i18n

```python
self.i18n.contribute(
    locale="zh-CN",
    messages={
        "hello": "你好",
    },
)
```

## stubs

stubs provider 由插件贡献，用户在设置中选择 provider/profile 组成 layers。

```python
from pathlib import Path

root = Path(self.path.plugin()) / "stubs"

self.stubs.contribute(
    provider_id="micropython-stubs-example",
    kind="micropython",
    version="1.0.0",
    profiles=[
        {
            "id": "generic",
            "label": "MicroPython Generic",
            "path": str(root / "generic"),
            "priority": 10,
        },
        {
            "id": "esp32",
            "label": "MicroPython ESP32",
            "path": str(root / "esp32"),
            "priority": 20,
        },
    ],
    aliases=["micropython", "esp32"],
)
```

## 初始化用户设置

Data 插件可以在首次贡献时初始化设置，但不应该覆盖用户已有配置。

示例：

```python
layers = self.settings.micropython_stubs.get_layers(...)
if layers:
    self.message.warning("已检测到现有 Stubs Layers，未覆盖用户配置")
else:
    self.settings.micropython_stubs.set_enabled(True)
    self.settings.micropython_stubs.set_layers([
        {"provider": "micropython-stubs-example", "profile": "generic"},
        {"provider": "micropython-stubs-example", "profile": "esp32"},
    ])
    self.message.success("MicroPython Stubs Layers 已配置")
```

## 所有权规则

- 插件只能贡献或撤销属于自己的数据。
- IDE 按插件 ID 管理 Contribution。
- 禁用插件会停用其 Contribution。
- 卸载插件会删除其 Contribution。

更多 MicroPython stubs 设计见 [MicroPython Stubs](../micropython_stubs.md)。
