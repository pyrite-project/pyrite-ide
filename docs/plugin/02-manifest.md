# 插件清单 plugin.toml

每个插件必须包含 `plugin.toml`。IDE 使用该文件识别插件、显示插件信息、判断插件类型、平台支持和权限。

## 基本结构

```toml
[general]
name = "Plugin Name"
id = "plugin-id"
version = "1.0.0"
author = "Author"
description = "Optional description"
type = "ui"
auto_start = false

[permissions]
ui = true
file = ["read"]

[platform]
linux = true
macos = true
windows = true
android = true
```

## general

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `name` | 是 | 插件显示名称 |
| `id` | 是 | 插件唯一 ID，建议使用小写、数字、短横线 |
| `version` | 否 | 插件版本，默认 `0.0.0` |
| `author` | 否 | 作者 |
| `description` | 否 | 描述 |
| `type` | 否 | `ui`、`service`、`data`，默认 `ui` |
| `auto_start` | 否 | 是否自动启动，主要用于 service 插件 |

## type

```toml
type = "ui"
type = "service"
type = "data"
```

- `ui`：显示页面，通常由用户进入插件页面后使用。
- `service`：后台服务，可启动/停止。
- `data`：运行一次贡献数据，不显示启动/停止按钮。

## permissions

权限可以写成布尔值或动作列表：

```toml
[permissions]
file = true
editor = ["read"]
settings = ["read", "write"]
data = true
```

`true` 表示启用该资源的所有标准动作。例如：

```toml
settings = true
```

等价于：

```toml
settings = ["read", "write"]
```

## platform

```toml
[platform]
linux = true
macos = true
windows = true
android = false
```

IDE 会根据当前平台判断插件是否可用。需要桌面能力的插件，例如桌面终端、特定本地进程能力，应谨慎启用 Android。
