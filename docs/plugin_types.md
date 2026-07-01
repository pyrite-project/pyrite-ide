# Plugin 类型设计

本文档定义 PyriteIDE 插件 SDK 的插件类型、生命周期和数据贡献模型。目标是让 UI、后台服务和数据插件拥有清晰边界，避免所有插件都继承同一个大而全的 `Plugin` 后产生生命周期和数据所有权混乱。

# 背景问题

当前 SDK 只有一个通用 `Plugin` 基类。它同时暴露 UI、文件、串口、设置、数据注册等能力，导致几个问题：

- `data` 插件也会走常驻插件流程，并产生空页面刷新等无意义行为。
- 数据注册结果只存在运行时 registry，插件停止后数据容易消失。
- stubs/theme/i18n 这类数据资源不应该依赖一个 Python 插件进程长期运行。
- UI/service 插件如果注册数据，无法明确区分“运行时注册项”和“长期贡献项”。
- 插件禁用、启用、卸载时，IDE 很难判断哪些数据应该清理、哪些数据应该保留。

因此 SDK 需要按插件类型拆分基类，并在 IDE 侧引入明确的 Contribution 模型。

# 核心术语

## Contribution / 贡献项

Contribution 是插件向 IDE 声明的一项可被 IDE 长期管理的数据贡献，例如 stubs provider、主题、语言包等。

Contribution 的生命周期由 IDE 管理，而不是由插件进程生命周期决定。

典型特征：

- 插件进程退出后，Contribution 仍然可以生效。
- App 重启后，IDE 可以从持久化记录恢复 Contribution。
- 插件禁用时，Contribution 停用。
- 插件重新启用时，IDE 重新运行插件并刷新 Contribution。
- 插件卸载时，Contribution 被删除。

## Runtime Registration / 运行时注册项

Runtime Registration 是插件运行期间临时注册的数据。

典型特征：

- 插件停止后自动清理。
- 不跨插件进程生命周期。
- 适合 UI/service 插件根据运行时状态动态提供的数据。

## Contribute / 贡献

Contribute 是创建 Contribution 的动作。它表达“这个数据由插件贡献给 IDE 管理”。

## Revoke / 撤销贡献

Revoke 是插件主动撤销自己创建的 Contribution 的动作。插件只能撤销自己拥有的数据，不能撤销其他插件的数据。

# SDK 基类拆分

SDK 应提供以下基类：

```python
class BasePlugin:
    ...

class UiPlugin(BasePlugin):
    ...

class ServicePlugin(BasePlugin):
    ...

class DataPlugin(BasePlugin):
    ...

class Plugin(UiPlugin):
    pass
```

`Plugin` 仅作为 UI 插件的默认入口，新插件应直接使用明确类型的基类。

# BasePlugin

`BasePlugin` 提供所有插件共有的基础能力。

建议包含：

- `bridge`
- `path`
- `settings`
- 输出/日志基础能力
- 基础生命周期钩子

`BasePlugin` 不应该直接暴露 UI 页面能力，也不应该默认暴露所有 IDE API。

# UiPlugin

`UiPlugin` 用于有可视界面、页面、交互控件的插件。

建议能力：

- UI pages / widgets
- router
- editor
- file / board
- serial
- persistence
- settings
- theme / i18n / stubs 数据注册 API

默认数据语义：

- `register()` 默认创建 Runtime Registration。
- 插件停止后，运行时注册项自动清理。
- 如果需要创建 Contribution，必须显式调用 `contribute()`。
- 创建 Contribution 后，应允许调用 `revoke()` 撤销。

理由：UI 插件通常随页面或用户交互运行，它注册的数据很可能和运行状态相关。默认长期保存这些数据会产生不可预期的残留。

# ServicePlugin

`ServicePlugin` 用于后台服务、设备监听、语言服务代理、同步任务等插件。

建议能力：

- file / board
- serial
- persistence
- settings
- theme / i18n / stubs 数据注册 API
- 后台任务生命周期

默认数据语义：

- `register()` 默认创建 Runtime Registration。
- 插件停止后，运行时注册项自动清理。
- 如果需要创建 Contribution，必须显式调用 `contribute()`。
- 创建 Contribution 后，应允许调用 `revoke()` 撤销。

理由：Service 插件可能动态生成数据，例如根据设备连接状态生成 stubs 或根据运行时环境提供能力。这类数据通常应跟随服务生命周期，而不是默认成为 IDE 长期数据。

# DataPlugin

`DataPlugin` 用于只贡献数据、不需要常驻运行的插件。

典型用途：

- 主题包
- 语言包
- MicroPython stubs 包
- 代码片段包
- 板卡元数据包

建议能力：

- `path`
- `settings` 的必要只读能力
- theme / i18n / stubs 等 contribute API
- 不暴露 pages
- 不触发 page refresh
- 不要求常驻进程

入口方法：

```python
class MyDataPlugin(DataPlugin):
    def on_contribute(self):
        ...
```

`on_contribute()` 表达“运行插件以贡献数据”。它比 `on_start()` 更准确，因为 data 插件不是启动一个长期服务。

运行语义：

- 安装时运行一次 `on_contribute()`。
- 启用时运行一次 `on_contribute()`。
- 贡献完成后插件进程可以退出。
- IDE 持久记录 Contribution。
- App 重启后不需要再次运行 data 插件即可恢复已启用 Contribution。
- 禁用后再启用，需要再次运行插件刷新 Contribution。

默认数据语义：

- `register()` 默认等同 `contribute()`。
- DataPlugin 创建的是 Contribution，不是 Runtime Registration。

理由：data 插件本质上是数据包或贡献脚本。要求它长期运行会浪费资源，并把静态数据错误地绑定到进程生命周期。

# 数据 API 建议

以 stubs 为例：

```python
self.stubs.contribute(
    provider_id="micropython-stubs-example",
    profiles=[...],
)

self.stubs.register_runtime(
    provider_id="runtime-device-stubs",
    profiles=[...],
)

self.stubs.revoke(provider_id="micropython-stubs-example")
```

theme 和 i18n 应采用一致命名：

```python
self.theme.contribute("theme_id", data)
self.theme.register_runtime("theme_id", data)
self.theme.revoke("theme_id")

self.i18n.contribute("zh-CN", messages)
self.i18n.register_runtime("zh-CN", messages)
self.i18n.revoke("zh-CN")
```

# IDE 内部数据模型

IDE 应维护两类数据源：

```text
enabled contributions + live runtime registrations
```

建议记录结构：

```text
DataContributionRecord
- pluginId
- pluginVersion
- contributionType: stubs/theme/i18n/...
- contributionId: provider_id/theme_id/locale/...
- payload
- enabled
- registeredAt
```

Runtime Registration 可使用相似结构，但不写入长期存储，且绑定到运行中的 `PluginRunManager`。

活动 registry 由 Contribution 和 Runtime Registration 合并得到。

# 生命周期规则

## 安装 DataPlugin

1. 解包插件。
2. 运行插件一次。
3. 插件调用 contribute API。
4. IDE 保存 Contribution。
5. 插件进程退出。
6. IDE 刷新相关消费者，例如主题列表、语言包、LSP stubs 配置。

## 启用 DataPlugin

1. 标记插件启用。
2. 运行插件一次。
3. 重新注册 Contribution。
4. 覆盖旧 Contribution。
5. 刷新消费者。

## 禁用 DataPlugin

1. 标记插件禁用。
2. 从 active registry 移除该插件的 Contribution。
3. 保留插件文件。
4. 可保留 Contribution 记录但标记 inactive，也可以删除 active contribution 记录。
5. 刷新消费者。

## 卸载 DataPlugin

1. 删除插件文件。
2. 删除该插件的所有 Contribution 记录。
3. 从 active registry 移除相关数据。
4. 刷新消费者。

## 停止 UiPlugin / ServicePlugin

1. 清理 Runtime Registration。
2. 不删除该插件已明确创建的 Contribution。
3. 如果插件希望主动撤销 Contribution，应调用 `revoke()`。

# 权限与所有权

所有数据注册都必须有明确 owner：

```text
owner = plugin_id
```

规则：

- 插件只能覆盖自己拥有的 Contribution 或 Runtime Registration。
- 不同插件注册相同 contribution id 应拒绝，除非该数据类型明确支持合并。
- 插件只能 revoke 自己拥有的数据。
- UI/service 插件创建 Contribution 应需要 manifest 权限或能力声明。

第一阶段可继续使用：

```toml
[permissions]
data = true
```

后续可细化为：

```toml
[contributions]
stubs = true
theme = true
i18n = true
```

# 与 MicroPython Stubs 的关系

MicroPython stubs 是典型 DataPlugin 场景。

示例：

```python
from pyrite_sdk.core.plugin import DataPlugin


class MicroPythonStubsPlugin(DataPlugin):
    def on_contribute(self):
        root = self.path.plugin()
        self.stubs.contribute(
            provider_id="micropython-stubs-example",
            profiles=[
                {"id": "generic", "path": str(root / "stubs" / "generic")},
                {"id": "esp32", "path": str(root / "stubs" / "esp32")},
            ],
        )


plugin = MicroPythonStubsPlugin()
plugin.run_once()
```

这避免了 stubs 依赖插件常驻运行。只要插件启用，IDE 就可以从 Contribution 恢复 provider/profile，并把路径传给 LSP。

# 设计理由

## 降低资源占用

DataPlugin 不需要常驻 Python 进程。注册完成后退出，可以减少后台进程、端口占用和消息循环复杂度。

## 生命周期更符合用户预期

用户安装主题包、语言包或 stubs 包后，期望数据持续可用，而不是依赖插件进程是否仍在运行。

## 避免数据残留

UI/service 插件默认只创建 Runtime Registration，停止后自动清理。只有显式 contribute 的数据才跨进程存在，并且可 revoke。

## 让禁用和卸载语义清晰

禁用表示 Contribution 不再生效；卸载表示 Contribution 和插件文件都被移除。

## 便于未来扩展

Contribution 模型可复用于主题、语言包、stubs、板卡元数据、代码片段等数据类型。

# 迁移计划

1. SDK 使用 `BasePlugin`、`UiPlugin`、`ServicePlugin`、`DataPlugin`。
2. 新增 `contribute` / `register_runtime` / `revoke` API。
3. IDE 增加 Contribution 存储模型。
4. `DataRegistry` 区分 Contribution 和 Runtime Registration。
5. 修改 data 插件运行逻辑：安装/启用时 run-once，完成后退出。
6. 禁用/卸载插件时按 owner 清理 Contribution。
7. stubs provider 改为 Contribution 驱动。
8. stubs 设置页改成 provider/profile 选择器。
9. 文档和示例插件迁移到 `DataPlugin.on_contribute()`。
