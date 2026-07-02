# 权限模型

插件必须在 `plugin.toml` 中声明所需权限。IDE 在处理 SDK 命令时会检查对应权限。

## 权限写法

```toml
[permissions]
ui = true
file = ["read"]
settings = ["read", "write"]
data = true
serial = true
```

`true` 表示授予该资源的标准动作。

## 资源与动作

| 资源 | 动作 | 说明 |
| --- | --- | --- |
| `ui` | `view`, `navigate` | 页面、导航 |
| `file` | `read`, `write` | 本地项目文件 |
| `board` | `read`, `write` | 开发板文件 |
| `editor` | `read`, `write` | 编辑器内容、标签页 |
| `persistence` | `read`, `write` | 插件持久化数据 |
| `tab` | `create`, `manage` | 标签页操作 |
| `settings` | `read`, `write` | IDE 设置 |
| `serial` | `read`, `write` | 串口状态和操作 |
| `data` | `read`, `write` | theme、i18n、stubs 等数据贡献 |

## 常见组合

UI 插件：

```toml
[permissions]
ui = true
file = true
editor = true
settings = ["read"]
```

Service 插件：

```toml
[permissions]
serial = true
persistence = true
settings = ["read"]
```

Data 插件贡献 stubs 并写入默认设置：

```toml
[permissions]
data = true
settings = true
```

## 权限不足时

如果权限不足，IDE 会返回错误，例如：

```text
Permission denied: settings:write
```

处理方式：

1. 检查 `plugin.toml` 是否声明对应资源。
2. 检查动作是否包含 `read` 或 `write`。
3. 重新打包并重新安装插件。
