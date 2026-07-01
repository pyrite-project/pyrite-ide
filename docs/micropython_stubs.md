# MicroPython Stubs 集成设计

本文档描述 PyriteIDE 对 MicroPython stubs 的推荐集成方案，目标是让 IDE、插件、任意 LSP 和用户项目都能以统一方式消费类型存根。

# 目标

- 支持 MicroPython 通用模块、port 专用模块和开发板私有模块的类型补全。
- 支持由插件携带、下载或生成 stubs，并注册给 IDE。
- 支持多个 stubs 同时启用，例如 `generic + esp32 + board-specific`。
- stubs 数据与具体 LSP 实现解耦，pylsp、pyright 或其它语言服务都可以消费同一套 registry。
- 不修改用户项目目录，不依赖全局 Python site-packages。

# 核心概念

## Stubs Provider

Stubs provider 是 stubs 数据来源，通常由一个 data plugin 注册。

每个 provider 必须有全局唯一的 `provider_id`。默认建议使用插件 id，避免冲突。

```json
{
  "provider_id": "micropython-stubs-official",
  "kind": "micropython",
  "version": "1.24.0",
  "profiles": []
}
```

## Stubs Profile

Profile 是 provider 内部的一个 stubs 集合，例如 `generic`、`esp32`、`rp2` 或某块开发板。

`profile_id` 只需要在同一个 provider 内唯一，不要求全局唯一。最终引用 stubs 时必须使用 `{provider_id, profile_id}` 复合键。

```json
{
  "id": "esp32",
  "label": "MicroPython ESP32",
  "path": ".../stubs/esp32",
  "priority": 50
}
```

## Stubs Layer

一个实际生效的 stubs 配置是有序 layer 列表，而不是单一路径。

典型组合：

```json
[
  {"provider": "micropython-stubs-official", "profile": "generic"},
  {"provider": "micropython-stubs-official", "profile": "esp32"},
  {"provider": "my-board-stubs", "profile": "esp32-s3-zero"}
]
```

UI 中应表达为“上方优先级更高”。传给具体 LSP/Jedi 时可根据语言服务路径解析规则调整顺序，但 registry 内保存的顺序必须稳定、可解释。

# 插件注册流程

插件可以在包内携带 stubs，也可以在运行时安装到插件自己的数据目录，然后注册给 IDE。

推荐插件目录结构：

```text
plugin-root/
  plugin.toml
  __main__.py
  stubs/
    generic/
    esp32/
    rp2/
```

也可以运行时安装：

```text
plugin-data/
  micropython-stubs/
    generic/
    esp32/
```

插件侧 SDK 期望形式：

```python
self.stubs.register(
    provider_id="micropython-stubs-official",
    kind="micropython",
    version="1.24.0",
    profiles=[
        {"id": "generic", "path": ".../stubs/generic"},
        {"id": "esp32", "path": ".../stubs/esp32"},
    ],
)
```

如果不单独引入 `self.stubs`，也可以挂在 data API 下：

```python
self.data.register_stubs(...)
```

# Manifest 建议

插件可在 `plugin.toml` 中声明 stubs 能力，便于 IDE 安装后静态扫描。

```toml
[plugin]
id = "micropython-stubs-official"
type = "data"

[data.stubs]
kind = "micropython"
provider_id = "micropython-stubs-official"
version = "1.24.0"
root = "stubs"
profiles = ["generic", "esp32", "esp8266", "rp2"]
```

`provider_id` 可省略，省略时默认为插件 id。

# 冲突规则

## Provider 冲突

不允许两个不同插件注册同一个 `provider_id`。

- 如果同一个插件重复注册同一个 `provider_id`，视为刷新或升级，允许覆盖。
- 如果不同插件注册同一个 `provider_id`，拒绝后注册者，并向输出栏写入 warning，SDK 返回 error。

原因：自动合并会让版本、来源、路径和优先级不可解释，也可能引入安全问题。

## Profile 重名

允许不同 provider 下存在同名 profile，例如多个 provider 都提供 `generic` 或 `esp32`。

用户配置和 LSP 消费时必须使用 `{provider, profile}`，不能只使用 `profile`。

## Alias

可以支持 alias 用于搜索或推荐，但 alias 不应作为唯一引用 id。

```toml
[data.stubs]
provider_id = "my-custom-stubs"
aliases = ["micropython-stubs"]
```

alias 冲突不覆盖已有 provider。

# IDE Registry

IDE 需要在 `DataRegistry` 中维护 stubs provider 列表。

建议数据结构：

```dart
class StubsProviderEntry {
  final String pluginId;
  final String providerId;
  final String kind;
  final String version;
  final List<StubsProfileEntry> profiles;
}

class StubsProfileEntry {
  final String id;
  final String label;
  final String path;
  final int priority;
}
```

当插件停止、卸载或禁用时，应移除该插件注册的 provider。

# 设置项

建议新增设置：

```text
micropython.stubs.enabled: bool
micropython.stubs.layers: list
micropython.stubs.auto_detect_layers: bool
micropython.stubs.extra_paths: list
```

`layers` 示例：

```json
[
  {"provider": "micropython-stubs-official", "profile": "generic"},
  {"provider": "micropython-stubs-official", "profile": "esp32"},
  {"provider": "my-board-stubs", "profile": "esp32-s3-zero"}
]
```

UI 建议：

- “启用 MicroPython Stubs” 开关。
- “Stubs 层级列表”，可添加、删除、排序。
- 每层显示 provider、profile、version、path。
- 标记来源：自动检测、用户手动、项目配置。

# LSP 消费流程

stubs 消费应由 IDE 的 LSP 创建层统一完成，而不是放进某个具体 LSP 插件。pylsp、pyright、basedpyright 或用户自定义 LSP 都应收到同一份 IDE 解析结果。

IDE 创建 LSP 连接时：

1. 读取 `micropython.stubs.enabled`。
2. 读取 `micropython.stubs.layers` 和 `micropython.stubs.extra_paths`。
3. 通过 IDE registry 将 `{provider, profile}` 解析成实际路径。
4. 将 paths 映射到 CodeForge 的 `workspaceConfiguration`，用于响应 LSP 的 `workspace/configuration` 请求，例如 `python.analysis.extraPaths`、`basedpyright.analysis.extraPaths`、`pylsp.plugins.jedi.extra_paths`。
5. 对 stdio LSP，同时将 paths 追加到该 LSP 进程的 `PYTHONPATH`。

具体 LSP 是否请求配置取决于其实现；stdio Python LSP 至少仍可通过 `PYTHONPATH` 获得 Python stubs 搜索路径。

# 自动检测

自动检测可以作为后续能力加入，不建议第一阶段强依赖。

可选来源：

- 连接设备后执行 `os.uname()`。
- 读取 `sys.implementation`。
- 根据板卡管理器中的 board id 映射。

自动检测只生成推荐 layers，用户应能手动覆盖。

# 安全与边界

- stubs 插件只能注册自身插件目录或自身数据目录下的路径。
- 不建议允许插件注册任意系统路径，除非经过权限确认。
- 不修改用户项目目录。
- 不使用全局 Python site-packages 作为默认安装位置。
- provider 冲突必须拒绝，不自动合并。

# 实施顺序

1. 扩展 `DataRegistry`，增加 stubs provider/profile 数据结构。
2. 扩展 Dart SDK API：`sdk.stubs.register/list/get` 或 `sdk.data.stubs.register`。
3. 扩展 Python SDK：`self.stubs` 或 `self.data.stubs`。
4. 新增 MicroPython stubs 设置项和设置 UI。
5. 在 IDE 的 LSP 创建层统一注入 stubs 初始化参数和 stdio 环境变量。
6. 增加自动检测和推荐 layers。
7. 增加 stubs 插件安装/更新示例。
