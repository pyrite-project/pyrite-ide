# PyriteIDE 插件系统重构执行任务

> 状态：待实施  
> 适用仓库：`pyrite_ide`、`E:\Can1425\pyrite-sdk`  
> 执行原则：严格按任务编号推进；前一任务未达到验收标准时，不开始后一任务；本轮是破坏式升级，不提供向下兼容。

## 1. 文档目的

本文档把插件系统重构拆分为可以逐项实现、测试和提交的任务。它同时是本轮重构的架构约束，后续实现如果需要改变本文中的核心决策，应先更新本文并记录原因，而不是直接在代码中形成第二套模型。

### 1.1 向下兼容策略

- 不兼容旧协议、旧 Manifest、旧 SDK 构造方式、WebSocket 插件传输或 RFW 插件 UI。
- 不实现 compatibility adapter、legacy renderer、fallback transport 或旧入口。
- 新实现可直接删除被替换的代码、依赖、fixture 和文档；旧插件必须升级后才能安装和运行。
- 已完成任务记录中的 WebSocket、RFW 和 legacy 内容仅描述当时基线，不构成后续兼容要求。

本轮重构的最终目标是：

1. 保留 `python_runtime` WIP 分支的全局单例 CPython 解释器设计。
2. 使用 `PythonBridge` 替换本地插件正式运行路径上的 WebSocket。
3. 保留版本化 RPC 协议，不把 Python 对象或 Dart 对象直接跨运行时传递。
4. 将插件 UI 从以 RFW 页面为中心迁移到宿主管理的原生 Flutter 视图。
5. UI 插件通过 Manifest 贡献导航容器、视图、命令、菜单和配置。
6. 桌面端侧边导航栏与移动端 Drawer 从同一个导航注册表生成。
7. 插件中心列表项点击后打开插件详情页，不再直接打开插件 UI 页面。
8. 提供通用插件事件总线、编辑器服务、运行时服务和设备事件。
9. UI 首次使用快照初始化，后续使用带版本号的增量 patch。
10. 使用宿主原生的虚拟列表、树、表格、大纲和变量检查器承载高频/大数据 UI。
11. 以大纲视图和变量视图作为新架构的两个端到端验收插件。
12. 补齐权限、上下文隔离、背压、超时、取消、监控和运行时恢复。

## 2. 已确定的架构决策

### 2.1 Python 运行时

- 使用一个进程内、全局单例的 CPython 解释器。
- 多个插件可以在该解释器中同时处于活动状态。
- 每个插件拥有独立的逻辑会话、消息通道、任务队列和生命周期。
- 不以 OS 子进程或 CPython 子解释器作为本轮插件隔离基础。
- 插件隔离是协作式隔离，不是安全沙箱或崩溃隔离。
- 插件失控且无法协作停止时，最终恢复手段是重启整个 Python runtime。

### 2.2 传输层

- 正式本地运行使用 `PythonBridge`。
- 插件通信只使用 `PythonBridge`；正式切换后删除 WebSocket transport、依赖和诊断 fallback。
- 上层 `PluginRunManager`、权限处理器和业务 API 只依赖抽象的 `PluginTransport`。
- bridge native callback 只负责把消息投递到有界队列，不直接执行插件业务。

### 2.3 UI 模型

- Flutter 宿主拥有导航、路由、视图实例、主题、焦点、可见性和高性能控件。
- Python 插件提供 Manifest、数据模型、增量 patch、命令处理和事件处理。
- 插件不能动态加载任意 Dart `Widget` 或执行任意 Dart 代码。
- 插件可以组合宿主提供的大量通用 Flutter 组件。
- 大纲、变量、日志、文件树、数据表等高频场景使用宿主原生复合控件。
- 插件 UI 只使用宿主管理的原生 renderer；原生视图完成后删除 RFW 插件运行路径。

### 2.4 贡献点与激活

- 插件通过 Manifest 静态声明导航容器、视图、命令、菜单和配置。
- `ui` 类型插件必须至少声明一个导航容器。
- 注册贡献点不等于启动 Python 插件。
- 插件由 `onView`、`onCommand`、`onLanguage` 等 activation event 延迟启动。
- 主导航容器不允许运行时随意动态创建；临时命令和视图内操作可在后续支持动态注册。

### 2.5 增量更新

- 首次打开视图允许发送完整 snapshot。
- snapshot 之后只发送增量 patch；版本不一致时才重新同步 snapshot。
- 所有集合节点使用稳定 ID/key。
- 大型集合必须虚拟化和分页/懒加载。
- patch 以事务批量应用，一批 patch 只发布一次 Flutter 状态。

## 3. 明确不在本轮范围内的能力

- 不实现第三方插件的 OS 级安全沙箱。
- 不实现每插件独立 CPython 子解释器。
- 不保证任意 native Python extension 崩溃后 IDE 仍存活。
- 不允许插件上传或动态加载 Dart/Flutter 二进制代码。
- 不为任意自定义 GPU/3D 渲染实现通用协议；此类能力后续使用受限 Canvas、WebView 或专用宿主组件处理。
- 不提供 RFW 或旧 Manifest 的兼容迁移层。

## 4. 当前实现基线与已知问题

### 4.1 当前 UI

- `lib/pages/plugins/main.dart` 中的 `PluginBody` 使用 `Runtime`、`DynamicContent` 和 `RemoteWidget` 渲染 RFW。
- 插件列表中的 UI 插件点击后进入 `/plugins/body?id=...`。
- `lib/features/function_page.dart` 中的扩展面板由 IDE 固定创建，插件无法注册导航容器和面板。
- `sdk.var.set` 能更新数据，但页面结构仍依赖完整 RFW 文本和 `page.to_rfw()`。
- 没有稳定节点 ID、结构 patch、事务、revision、虚拟树和原生变量检查器。

### 4.2 当前通信

- Flutter 侧 `PluginRunManager` 使用 WebSocket 连接插件。
- Python SDK `Bridge` 在 localhost 启动 WebSocket server。
- `python_runtime` 已提供进程内 `PythonBridge` 与多 native port 支持。
- 当前协议版本仍为 `0.0`，没有正式初始化握手和 capability negotiation。

### 4.3 当前单例解释器风险

- `runPersistentPython` 在一个解释器中通过线程执行多个入口。
- 插件共享 `sys.modules`、`sys.path`、`os.environ`、第三方库全局状态和 GIL。
- `plugin_run_manager_provider.dart` 会修改 `Directory.current`，这是 Dart 进程级全局状态。
- 插件启动上下文需要串行建立，并在插件对象中捕获，不能长期依赖全局环境变量。
- 插件包必须使用唯一顶层模块命名空间，避免共享模块缓存冲突。

### 4.4 当前权限与上下文风险

- 空权限列表存在绕过权限检查的风险，权限应默认拒绝。
- 部分 SDK 命令尚未完整登记权限。
- API Provider 反复绑定最近的 `PluginRunManager`，可能把请求路由到错误插件上下文。
- 所有请求必须从消息会话中显式解析 `pluginId/sessionId`，不能使用“最近绑定”的全局状态。

### 4.5 当前事件和宿主服务缺口

- 没有通用事件订阅、取消订阅、过滤、节流和回放机制。
- 缺少统一的编辑器文档事件和符号查询 API。
- 缺少运行时 session、scope、variables、children、objectInfo API。
- `serial.run_python` 会打断设备程序并独占 REPL，不可作为变量视图后台轮询接口。

## 5. 目标架构

```text
Plugin Manifest
  -> ContributionRegistry
       -> NavigationRegistry -> NavigationRail / NavigationDrawer
       -> ViewRegistry       -> PluginViewHost
       -> CommandRegistry
       -> MenuRegistry
       -> ConfigurationRegistry

Host Services
  -> EditorDocumentService
  -> RuntimeInspectionService
  -> File/WorkspaceService
  -> DeviceService
  -> PluginEventBus

Plugin Runtime
  -> Singleton PythonRuntimeHost
       -> PluginSession A -> PythonBridge port A
       -> PluginSession B -> PythonBridge port B
       -> PluginSession C -> PythonBridge port C

Native Flutter UI
  -> snapshot + incremental patch
  -> VirtualList / TreeView / DataTable
  -> OutlineView / VariableInspector / LogView
```

## 6. 协议基础约定

### 6.1 Envelope

所有请求、响应和事件共用一个版本化 Envelope：

```json
{
  "protocolVersion": 1,
  "pluginId": "python-tools",
  "sessionId": "session-42",
  "generation": 3,
  "requestId": "req-16",
  "replyTo": null,
  "sequence": 120,
  "type": "sdk.view.patch",
  "payload": {}
}
```

规则：

- `pluginId` 标识插件安装实例。
- `sessionId` 标识一次激活会话。
- `generation` 在插件或整个 runtime 重启后递增。
- `requestId/replyTo` 用于请求响应。
- `sequence` 用于检测重复、乱序或丢失消息。
- 未识别的 `protocolVersion` 或不支持的 capability 必须返回明确错误。
- 旧 session/generation 的消息必须丢弃并记录诊断信息。

### 6.2 初始化握手

```text
ide.initialize
  -> SDK 校验版本和插件身份
sdk.initialize
  -> SDK 返回版本、capabilities、SDK 信息
ide.initialized
  -> 宿主确认会话可用
sdk.ready
  -> 插件业务初始化完成
```

### 6.3 消息类别

```text
ide.*   IDE 发给插件
sdk.*   插件发给 IDE

*.request / *.response  有响应的 RPC
*.event                 单向事件
*.snapshot              完整状态
*.patch                 增量状态
*.ack / *.nack          流量和版本确认
```

## 7. Manifest v2 草案

```toml
manifest_version = 2
id = "python-tools"
name = "Python Tools"
version = "1.0.0"
type = "ui"
protocol_version = 1

activation_events = [
  "onView:python-tools.outline",
  "onView:python-tools.variables",
  "onCommand:python-tools.refreshVariables"
]

permissions = [
  "editor.read",
  "runtime.inspect"
]

[[contributes.navigation_containers]]
id = "python-tools"
title = "Python"
icon = "code"
location = "primary"
order = 100

[[contributes.views]]
id = "python-tools.outline"
container = "python-tools"
title = "Outline"
renderer = "native.outline"
order = 10

[[contributes.views]]
id = "python-tools.variables"
container = "python-tools"
title = "Variables"
renderer = "native.variableInspector"
order = 20
when = "runtime.language == 'python'"

[[contributes.commands]]
id = "python-tools.refreshVariables"
title = "Refresh Variables"
icon = "refresh-cw"

[[contributes.menus]]
location = "view/title"
view = "python-tools.variables"
command = "python-tools.refreshVariables"
group = "navigation"

[[contributes.configuration]]
id = "python-tools.showPrivate"
title = "Show Private Variables"
type = "boolean"
default = false
order = 20
```

Manifest 规则：

- `manifest_version`、插件 `version` 和 `protocol_version` 分别版本化，不能互相代替；当前只接受 `manifest_version = 2` 和 `protocol_version = 1`。
- TOML 使用根级 snake_case 字段；权限使用 `resource.action` token，并在宿主内部规范化为 resource/action 映射。
- 所有贡献 ID 全局唯一，并以插件 ID 为前缀。
- `ui` 插件必须声明至少一个 `navigation_containers`。
- 导航容器由宿主同时映射到桌面 NavigationRail 和移动 NavigationDrawer。
- `renderer` 必须出现在宿主 capability 列表中。
- `when` 只能使用宿主定义的 context key 和受限表达式。
- 安装时完成结构、权限、ID 冲突、图标和 renderer 校验。

## 8. 事件系统草案

### 8.1 订阅协议

```json
{
  "type": "sdk.events.subscribe",
  "payload": {
    "subscriptionId": "sub-1",
    "topic": "editor.document.changed",
    "filter": {"language": "python"},
    "delivery": {
      "mode": "latest",
      "debounceMs": 100
    }
  }
}
```

```json
{
  "type": "ide.event.emit",
  "payload": {
    "subscriptionId": "sub-1",
    "topic": "editor.document.changed",
    "eventId": "evt-42",
    "documentId": "doc-7",
    "revision": 18,
    "changes": []
  }
}
```

投递模式：

- `every`：每个事件必须投递。
- `latest`：队列中只保留同 topic/filter 的最新事件。
- `batch`：时间窗口内批量投递。
- `debounce`：停止变化后投递。
- `throttle`：限制最高投递频率。

### 8.2 第一批事件

```text
editor.activeDocument.changed
editor.document.opened
editor.document.changed
editor.document.saved
editor.document.closed
editor.document.selection.changed

runtime.session.created
runtime.session.state.changed
runtime.program.started
runtime.program.paused
runtime.program.resumed
runtime.program.finished
runtime.backend.restarted
runtime.variables.changed

view.opened
view.closed
view.visibility.changed
view.focused

workspace.opened
workspace.changed
file.created
file.changed
file.deleted
file.renamed

device.connected
device.disconnected
device.state.changed
serial.data.received
serial.error
```

## 9. 原生视图协议草案

### 9.1 Snapshot

```json
{
  "type": "sdk.view.snapshot",
  "payload": {
    "viewId": "python-tools.outline",
    "revision": 1,
    "model": {
      "roots": ["symbol-1"],
      "nodes": {
        "symbol-1": {
          "label": "main",
          "kind": "function",
          "expandable": false
        }
      }
    }
  }
}
```

### 9.2 Patch

```json
{
  "type": "sdk.view.patch",
  "payload": {
    "viewId": "python-tools.outline",
    "baseRevision": 1,
    "revision": 2,
    "operations": [
      {
        "op": "update",
        "id": "symbol-1",
        "changes": {"label": "main_async"}
      }
    ]
  }
}
```

第一版操作集合：

```text
insert
update
remove
move
replaceChildren
setSelection
setLoading
setError
```

规则：

- `baseRevision` 必须等于宿主当前 revision。
- 一批 operations 在内存模型中全部成功后才能提交。
- 失败时不得提交部分操作，返回 `nack` 并要求 resync。
- 一批 operations 只触发一次状态发布。
- patch 发送端最多保留一个 in-flight revision；等待期间产生的更新应合并。

## 10. 任务执行规则

每个任务执行时必须：

1. 将任务状态从 `[ ]` 改为 `[~]`。
2. 只修改该任务范围内的行为；发现额外问题先记录到对应后续任务。
3. 同时更新 IDE 和 SDK 的协议模型，禁止只改一侧。
4. 添加与风险相匹配的单元、组件或集成测试。
5. 运行任务列出的验证命令。
6. 在任务下记录实际完成内容、偏差和测试结果。
7. 达到全部验收标准后改为 `[x]`，再开始下一任务。

状态含义：

```text
[ ] 未开始
[~] 进行中
[x] 已完成并验证
[!] 阻塞，需要明确决策
```

---

## T00：建立重构基线和测试夹具

状态：`[x]`  
依赖：无

### 目标

在改变行为前固定当前插件安装、启动、WebSocket 通信、RFW 页面和权限行为，避免后续无法区分既有缺陷与重构回归。

### 实现内容

- 为当前 Envelope 序列化/反序列化增加 fixture。
- 为 `PluginRunManager` handler 路由增加测试。
- 为插件 Manifest/TOML 解析增加 fixture。
- 为插件列表点击、详情弹窗和 `/plugins/body` 现有行为增加必要的 widget test。
- 在 SDK 中为 `Bridge` 的 request/response/callback 增加协议 fixture。
- 建立一个最小测试插件：启动、输出、调用一个 SDK API、展示一页 RFW、正常停止。
- 记录 Windows、Linux、macOS、Android 当前可运行情况；不能执行的平台明确记录为未验证。

### 预期文件

```text
test/core/sdk/
test/pages/plugins/
test/fixtures/plugins/
E:\Can1425\pyrite-sdk\tests\
```

### 验收标准

- fixture 可以被 IDE 和 SDK 两侧测试读取。
- 当前最小测试插件可以完成一次完整启动和停止。
- 后续替换传输时，可以复用同一组协议 fixture。

### 验证

```text
flutter test test/core/sdk test/pages/plugins
SDK 仓库现有测试命令
```

### 完成记录

- IDE 新增 `test/fixtures/protocol/legacy_v0_envelopes.json`、最小 legacy 插件 fixture，以及 Envelope、Manifest、handler 路由和插件列表/详情/RFW 页面测试。
- SDK 新增同形协议 fixture、`tests/test_protocol_fixtures.py`，并使用真实 WebSocket 子进程完成最小插件的启动、输出、`sdk.settings.get` 请求/响应、RFW 页面推送和 dispose 停止。
- Windows 已验证 IDE 协议/handler、SDK 协议、最小插件生命周期和 RFW fixture；Linux、macOS、Android 仍未验证，见 `doc/plugin_system_platform_baseline.md`。
- 验证通过：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`（49 tests）；`python -m unittest tests.test_protocol_fixtures -v`（4 tests）。
- SDK 全量基线 `python -m unittest discover -s tests -v` 当前有 9 个既有失败/错误（4 failures、5 errors）：缺失 `examples/ai_plugin`、`SizedBox` 可选尺寸处理、旧 callback 连字符断言，以及若干已有 RFW 示例断言。T00 未修改这些运行时行为，后续应单独归档/修复。

---

## T01：建立协议 v1、Envelope 和初始化握手

状态：`[x]`  
依赖：T00

### 目标

在更换传输前先让协议与 WebSocket 解耦，并建立版本、会话和能力协商。

### IDE 实现

- 定义 v1 Envelope 类型和严格校验。
- 增加 `pluginId/sessionId/generation/sequence`。
- 增加 request timeout、replyTo 校验和重复响应保护。
- 实现 `ide.initialize -> sdk.initialize -> ide.initialized -> sdk.ready`。
- 建立 capability 常量和协商结果对象。
- 未握手完成前只允许初始化、日志和错误消息。

### SDK 实现

- 建立相同的 Envelope 模型。
- 在 Bridge 启动时执行握手。
- 暴露协议版本、SDK 版本和 capability。
- 对不支持的宿主 capability 提供可诊断错误。

### 验收标准

- IDE/SDK fixture 完全一致。
- 错误版本、错误 pluginId、旧 generation、重复 sequence 均被拒绝。
- 插件在 `sdk.ready` 前不会注册视图或处理业务事件。
- 旧协议插件得到明确的不兼容提示，而不是无响应。

### 测试

- Envelope round-trip。
- 初始化成功、版本不匹配、超时、断开、重复消息。
- session 重启后旧消息丢弃。

### 完成记录

- IDE 与 SDK 已统一为协议 v1，线格式固定使用 `protocolVersion/pluginId/sessionId/generation/requestId/replyTo/sequence/type/payload/data/timestamp`。
- 完成四阶段握手和 `sdk.v1`、`rfw` capability 协商；握手前拒绝业务消息，并对 v0、畸形消息、错误会话/代次及重复或乱序 sequence 返回或记录明确协议错误。
- 增加请求超时、未知/重复 `replyTo` 防护；IDE 内部 handler 和 Python SDK 属性暂时保留旧字段别名兼容，但线上只发送规范 v1 字段。
- 两端 `protocol_v1_handshake.json` SHA-256 一致：`74899D1C7A333C4B8BF2CE05A7E77B5B847E5568E5A2F11429A3AC346E97827B`。
- 验证通过：Dart T01 定向测试 17 tests；SDK T01 测试 5 tests；SDK callback/dispose 影响测试 4 tests；IDE 回归 52 tests；Dart analyzer 零问题；Python 修改文件语法编译通过；两仓库 `git diff --check` 无错误。
- SDK 全量基线仍为 T00 已记录的 9 个既有问题（4 failures、5 errors），T01 未新增回归。

---

## T02：修复权限默认策略和多插件上下文路由

状态：`[x]`  
依赖：T01

### 目标

在增加更多 API 前消除 fail-open 权限和“最近绑定 PluginRunManager”导致的跨插件访问风险。

### IDE 实现

- 权限默认策略改为 fail-closed。
- 完整登记现有 SDK command 对应权限。
- handler 根据 Envelope 中的 plugin/session 查找上下文。
- 移除 API Provider 中可被其他插件覆盖的最近绑定状态。
- 每个权限拒绝返回稳定错误码并写入权限日志。
- 将权限分解到操作级，例如 `editor.read`、`editor.write`、`runtime.inspect`。

### SDK 实现

- 为权限拒绝提供专用异常类型。
- SDK API 文档标记每个操作所需权限。
- 不把权限缺失误判为 API 不存在或网络错误。

### 验收标准

- 空权限插件不能调用任何受保护 API。
- 两个插件并发请求时始终使用各自权限和路径上下文。
- 权限监视页可以区分允许、拒绝、未知命令。

### 测试

- 空权限、最小权限、错误权限。
- 两插件交错请求的上下文隔离测试。
- 权限表完整性测试：所有公开 `sdk.*` command 必须映射权限或声明为无需权限。

### 完成记录

- 权限检查改为 fail-closed：空权限、无关权限和未知命令均拒绝；修复旧 hierarchy 方向错误导致 `read` 可以错误满足 `write` 的提权漏洞。
- 所有现有 SDK API command 已登记操作级权限，`sdk.output.append` 与插件作用域路径请求明确声明为 public；完整性测试会扫描 API command 常量并阻止遗漏策略的新命令。
- 权限拒绝和未知命令分别返回稳定的 `permission_denied`、`unknown_command`，错误详情包含所需权限；权限日志和监视页支持 allowed、denied、unknown 三态，并跳过高频 output 日志以避免淹没审计记录。
- 所有 API provider 已移除可覆盖的最近绑定 `PluginRunManager` 状态；handler 显式捕获所属 manager，分发前再次校验 `pluginId/sessionId/generation`。持久化路径、Tab 页面、数据贡献和消息日志均使用请求所属插件上下文。
- SDK 新增 `SdkApiError`、`PermissionDeniedError`、`UnknownCommandError` 和 `InvalidPluginContextError`；Bridge 将错误响应转换为专用异常传给 callback，并新增 `docs/api/permissions.md` 权限表。
- 双插件测试使用不同 session、不同数据目录和不同权限交错请求，验证可写插件成功、只读插件稳定拒绝，且读取结果不会串路。
- 验证通过：IDE 定向 18 tests、加强后的权限/上下文 10 tests、完整回归 57 tests；Dart analyzer 零问题；SDK T02 与协议定向 7 tests；Python 语法检查及两仓库 `git diff --check` 通过。
- SDK 全量为 87 tests，仍是 T00 已记录的 4 failures、5 errors，没有 T02 新回归。

---

## T03：抽象 PluginTransport

状态：`[x]`  
依赖：T01、T02

### 目标

让 `PluginRunManager` 不再直接依赖 WebSocket，为 PythonBridge 迁移建立稳定边界。

### IDE 实现

定义：

```dart
abstract interface class PluginTransport {
  Stream<Uint8List> get messages;
  Stream<PluginTransportState> get states;
  Future<void> start();
  Future<void> send(Uint8List message);
  Future<void> close();
}
```

- 将现有 WebSocket 代码移动到 `WebSocketPluginTransport`。
- `PluginRunManager` 只接收 `PluginTransport`。
- 明确 connecting/ready/closing/closed/failed 状态。
- close 必须幂等。
- transport 错误不能直接绕过 PluginRunManager 生命周期。

### SDK 实现

- 将 WebSocket 收发从 `Bridge` 业务分发器中抽出。
- 定义 Python `Transport` protocol/ABC。
- WebSocket transport 仅作为 T04/T05 切换前的临时实现，不能进入最终交付。

### 验收标准

- T03 阶段暂时仍使用 WebSocket，但 `PluginRunManager` 不 import WebSocket 类型；T05 必须直接删除该实现。
- IDE 与 SDK 的业务 handler 不知道底层传输类型。
- T00 fixture 全部通过。

### 测试

- FakeTransport 收发、断开、重复 close、错误传播。
- 现有 WebSocket 集成测试。

### 完成记录

- IDE 新增 `PluginTransport`、`PluginTransportState` 和 `WebSocketPluginTransport`，统一使用字节消息流并明确 connecting/ready/closing/closed/failed 状态；`PluginRunManager` 改为只注入抽象 transport，连接重试、协议握手、挂起请求失败和停止清理仍由 manager 管理。
- SDK 新增 `Transport` ABC、`TransportState`、`TransportClosedError` 和 `WebSocketTransport`；`Bridge` 的业务分发只通过 transport 读取、发送和管理服务生命周期，不再 import 或调用 `websockets`。
- 两侧均保留 WebSocket 作为当前默认兼容实现，协议 v1 Envelope 和握手线格式未改变。
- 新增 FakeTransport 收发、断开错误传播、幂等关闭测试，并复用真实 WebSocket 最小插件测试验证启动、握手、SDK API、RFW 更新和 dispose 停止。
- 验证通过：IDE 59 tests、analyzer 零问题；SDK T03 定向 14 tests 和 Python 语法检查通过；SDK 全量 90 tests 仍为既有 4 failures、5 errors，无新增回归；两仓库 `git diff --check` 无错误。

---

## T04：实现 PythonBridgePluginTransport

状态：`[!]`  
依赖：T03

### 目标

在四个平台提供进程内 Dart/Python 字节传输，不改动上层 RPC 语义。

本任务只建立并验证 PythonBridge transport；正式路径切换和 WebSocket 删除属于 T05，不提供两种 transport 并存的最终配置。

### IDE 实现

- 每个 PluginSession 创建一个 `PythonBridge`。
- 在 Python 启动前创建 ReceivePort，并把 native port 传入启动上下文。
- `PythonBridge.messages` 转换为 transport message stream。
- `send()` 对 handler 未就绪提供有限重试和 deadline。
- transport close 时取消 subscription、关闭 ReceivePort、清理队列。
- 第一版使用一个 channel；预留 control/data channel capability。

### SDK 实现

- 新增 `DartBridgeTransport`。
- 使用 `dart_bridge.set_enqueue_handler_func(port, handler)` 注册。
- native handler 只调用 `loop.call_soon_threadsafe` 把 bytes 放入 asyncio 有界队列。
- Python 到 Dart 使用 `dart_bridge.send_bytes`。
- transport dispose 时注销 handler。
- 支持 Dart VM session restart 后更新 port 并重新注册。

### 验收标准

- 同一解释器中至少三个插件拥有不同 channel，消息无串路。
- IDE 到 Python、Python 到 IDE 均能传输空消息、小消息和大消息。
- handler 未注册时不会无限重试。
- native callback 中不执行业务 handler。
- Windows、Linux、macOS、Android 均完成至少一次真机/实际 runner 验证。

### 测试

- 1 B、1 KB、64 KB、1 MB payload round-trip。
- 多插件交错消息。
- 插件启动慢、插件提前退出、Dart VM session restart。
- 连续创建/销毁 100 次 channel 的泄漏检查。

### 当前完成记录

- IDE 已新增 `PythonBridgePluginTransport`，每个实例持有独立 `PythonBridge`，暴露 native port/channel label 启动上下文，并实现有限重试、deadline、状态流和幂等关闭。
- SDK 已新增 `DartBridgeTransport`，native callback 只复制 bytes 并通过 `loop.call_soon_threadsafe` 投递到有界 `asyncio.Queue`；支持 handler 注销、幂等关闭和 Dart VM session restart 后按 channel label 重绑 port。
- 单元测试覆盖 0 B、1 B、1 KB、64 KB、1 MB 双向消息、三个 channel 隔离、慢启动、handler 缺失 deadline、Python channel 提前关闭、队列溢出、session restart 和连续 100 次创建/销毁。
- Windows 与 Android 16 arm64 真机均使用真实嵌入式 CPython、真实 `dart_bridge` 和三个 SDK transport 完成全尺寸 payload 往返；集成 fixture 中的 transport 模块与当前 SDK 源码按换行规范化后完全一致。
- Linux、macOS 当前没有可用实际 runner，尚未达到四平台验收条件；T04 因此保持阻塞。项目负责人已指示先行实施 T05，T04 的两平台补验仍未完成。

---

## T05：正式路径切换到 PythonBridge

状态：`[!]`  
依赖：T04

### 目标

本地插件只使用 PythonBridge，不再申请 TCP 端口或启动 WebSocket server。

### IDE 实现

- `plugin_run_manager_provider.dart` 默认创建 `PythonBridgePluginTransport`。
- 移除正式路径的 `freePort()`、localhost URL 和连接重试。
- 插件详情/监视页显示当前 transport 类型。
- 删除 `WebSocketPluginTransport` 及插件通信相关测试和依赖。

### SDK 实现

- Bridge 只构造和使用 `DartBridgeTransport`。
- 删除 `WebSocketTransport`、`websockets` 依赖和 WebSocket 协议文档。
- SDK 启动上下文必须提供 native port/channel label，缺失时直接失败。

### 验收标准

- 默认启动过程中没有监听 localhost 端口。
- 所有 T00 协议行为在 PythonBridge 上通过。
- IDE 与 SDK 中不存在插件通信 WebSocket fallback。
- 旧的 TCP port 启动方式直接拒绝，不提供兼容入口。

### 测试

- 默认 transport 集成测试。
- 缺失/非法 native port 启动失败测试。
- 四平台 smoke test。

### 当前完成记录

- IDE 正式启动路径已只创建 `PythonBridgePluginTransport`，启动上下文仅传 native port/channel label；已删除插件 WebSocket transport、localhost/free-port 分配和连接重试，详情页与监视页会显示 transport 类型。
- SDK `Bridge` 默认只从 native 启动上下文构造 `DartBridgeTransport`；已删除 `WebSocketTransport`、`websockets` 依赖和插件 WebSocket 文档。旧 `PYRITE_IDE_PLUGIN_PORT` 启动方式会直接失败，不提供 fallback 或兼容入口。
- IDE 插件回归 66 tests、SDK T05 定向 20 tests、analyzer、Python 编译检查、依赖锁检查和两仓库 `git diff --check` 均通过；SDK 全量仍为此前记录的 4 failures、5 errors，没有新增回归。
- Windows 与 Android 16 arm64 实机均通过真实嵌入式 CPython/PythonBridge 三通道集成测试；Linux、macOS 当前没有可用实际 runner，四平台 smoke 尚缺两项，因此 T05 保持阻塞。

---

## T06：加固单例 PythonRuntimeHost 和 PluginSession

状态：`[x]`  
依赖：T05

### 目标

把全局单例解释器作为明确的宿主服务管理，避免插件自行竞争全局启动上下文。

### IDE 实现

- 新建 `PythonRuntimeHost`，集中执行 runtime start、plugin start/stop/restart。
- 建立 `PluginSession`：pluginId、sessionId、generation、transport、状态、启动时间。
- 插件初始化阶段使用全局启动锁串行化。
- 移除插件启动路径对 `Directory.current` 的修改。
- 路径全部使用绝对路径和显式 PluginContext。
- session 停止时清理 transport、请求、订阅、视图和贡献的运行时状态。

### SDK 实现

- 新增只读 `PluginContext`：id、session、pluginDir、dataDir、cacheDir、capabilities。
- 启动时捕获上下文，后续不重复读取可被覆盖的环境变量。
- 插件代码不得调用 `os.chdir` 或修改宿主管理的环境变量。
- 插件包和示例改用唯一顶层命名空间。

### 验收标准

- 并发启用多个插件时，初始化阶段按顺序完成。
- 插件运行后能并发处理各自 I/O。
- 任一插件看到的 PluginContext 始终正确。
- 停止一个插件不会关闭其他插件 channel。
- runtime 整体重启后 generation 递增，旧消息失效。

### 测试

- 并发启动 5 个测试插件。
- 不同插件目录、数据目录和 cache 访问。
- 启动中取消、启动失败、重复启动、整体 runtime 重启。

---

## T07：实现 Manifest v2 模型和校验器

状态：`[x]`  
依赖：T01、T02

### 目标

建立贡献点、激活事件和细粒度权限的持久格式。

### IDE 实现

- 增加 Manifest v2 Dart model、TOML 解析和 schema 校验。
- 支持 navigationContainers、views、commands、menus、configuration。
- 支持 activationEvents、when、renderer、order、icon。
- 校验全局 ID 前缀和冲突。
- `ui` 插件没有导航容器时拒绝安装/启用。
- 保存原始 manifest 和标准化后的 contribution model。

### SDK/工具实现

- SDK 提供 Manifest v2 model 或构建辅助类型。
- 更新示例插件和打包工具。
- 生成 manifest 时默认使用安全、最小权限。

### 版本策略

- 只接受 Manifest v2。
- v1、缺少版本或声明 RFW renderer 的插件直接拒绝安装/启用，并返回稳定错误码。

### 验收标准

- 合法 v2 manifest 可稳定 round-trip。
- ID 冲突、非法 renderer、非法 when、缺导航的 UI 插件被拒绝。
- v1、缺少版本和 RFW 插件均被明确拒绝。

### 测试

- golden fixtures：最小 UI、完整 UI、data、service、非法 manifest、拒绝 v1/RFW。

---

## T08：实现 ContributionRegistry 和 ContextKeyService

状态：`[x]`  
依赖：T07

### 目标

让安装/启用的插件向宿主注册贡献定义，而不启动 Python。

### IDE 实现

- 新增 ContributionRegistry，按 pluginId 原子注册/注销。
- 增加 Navigation/View/Command/Menu/Configuration 子注册表。
- 新增 ContextKeyService 和受限 when 表达式解析器。
- context key 改变时，只重新计算受影响贡献。
- 禁用、更新、卸载插件时原子删除其贡献。
- 注册失败时不得留下部分贡献。

### 第一批 context key

```text
editor.language
editor.hasDocument
runtime.language
runtime.state
device.connected
workspace.opened
plugin.enabled
view.active
```

### 验收标准

- 注册贡献不启动 Python runtime。
- 禁用插件后所有宿主入口立即消失。
- 更新插件时旧贡献和新贡献原子替换。
- when 表达式不能执行任意 Dart/Python 代码。

### 测试

- 重复 ID、部分失败回滚、context key 增量更新、禁用/卸载清理。

### 当前完成记录

- 新增受限 `WhenExpression`、`ContextKeyService` 和 `ContributionRegistry`，支持 Navigation/View/Command/Menu/Configuration 子注册表、按插件原子替换/注销、依赖 context key 的增量可见性计算及失败回滚；注册只处理 Manifest，不启动 Python。
- 插件冷启动、安装、更新、启用、禁用和卸载均同步宿主贡献快照；禁用或卸载后入口立即移除，更新在新 Manifest 验证通过后整体替换。
- 新增重复 ID、部分失败回滚、受限表达式、增量更新及生命周期清理测试。

---

## T09：侧边导航栏和 Drawer 动态注册

状态：`[x]`  
依赖：T08

### 目标

UI 插件启用后，在桌面 NavigationRail 和移动 NavigationDrawer 中出现同一个导航容器入口。

### IDE 实现

- 将固定导航项与 PluginNavigationRegistry 输出合并。
- 根据 order、启用状态和 when 排序/过滤。
- icon 使用宿主支持的稳定 token；未知 icon 使用 extension fallback。
- 点击导航项打开宿主管理的 view container，不允许插件直接修改主路由树。
- 保持桌面和移动选中状态一致。
- 插件禁用或贡献隐藏时，安全切换到可用内置页面。
- 保存最后激活的容器，但启动恢复时校验容器仍有效。

### 验收标准

- 启用 UI 插件后桌面和移动导航均出现入口。
- 点击入口触发 view activation，而不是跳转 `/plugins/body`。
- 禁用/卸载插件后入口和选中状态正确清理。
- 多插件顺序稳定，不因异步启动发生跳动。

### 测试

- NavigationRail widget test。
- NavigationDrawer widget test。
- 启用、禁用、when 切换、插件更新、当前项被删除。

### 当前完成记录

- 内置 NavigationRail、NavigationDrawer 与插件导航容器合并，按 `order`、插件 ID、容器 ID 稳定排序；支持 Manifest icon token 映射和未知图标 fallback。
- 插件入口使用宿主管理的 `/plugin-view` 路由，携带插件、容器和首个视图标识，不直接跳转旧的 `/plugins/body`；导航状态在桌面、平板和移动端共享。
- context key 隐藏、禁用或卸载当前容器时自动回退到文件页，避免保留失效选中索引。
- 已通过 NavigationRail/NavigationDrawer 动态入口 widget test、插件页面回归测试和 function page/routes/plugin host scoped analyzer。

---

## T10：重构插件中心和插件详情页

状态：`[x]`  
依赖：T07、T08、T09

### 目标

插件中心只承担发现和管理职责，列表项点击进入完整详情页。

### IDE 实现

- 新增 `/plugins/detail?id=...` 路由和详情页。
- 插件列表项点击改为详情页。
- 详情页显示版本、作者、类型、状态、权限、贡献点、配置、运行状态和错误。
- 提供启用、停用、卸载、更新和“打开”操作。
- “打开”调用 ViewCoordinator 打开插件导航容器。
- 删除原有仅用于详情的临时 dialog，或改成复用详情模型。

### 验收标准

- 插件列表项不再直接打开插件 UI。
- UI 插件详情页能列出导航、视图、命令和权限。
- 数据/服务插件详情页不显示无效的打开按钮。
- 所有管理操作完成后详情页实时更新。

### 测试

- 路由、详情内容、启停、卸载确认、无效旧插件错误状态。

---

## T11：实现 ActivationManager 和完整生命周期

状态：`[x]`  
依赖：T06、T08、T09

### 目标

贡献点注册与 Python 插件启动解耦，按 activation event 延迟启动。

### IDE 实现

- 实现 `onView`、`onCommand`、`onLanguage`、`onStartup`。
- 同一插件并发收到多个激活请求时只启动一次。
- 定义 installed/enabled/activating/active/deactivating/failed 状态机。
- 视图首次打开时等待 `sdk.ready`，展示宿主 loading/error 状态。
- view opened/closed/visibility/focus 变化进入事件总线。
- deactivate 自动清理 subscriptions、requests、views 和运行时动态贡献。

### SDK 实现

- 生命周期函数支持 sync/async handler。
- SDK 自动串行化 start/activate/deactivate/dispose。
- dispose 后拒绝发送新消息。

### 验收标准

- IDE 启动时不会启动所有插件。
- 点击插件导航项只激活对应插件。
- 同一插件多个视图共享一个 PluginSession。
- 启动失败可在详情页和视图中诊断并重试。

### 测试

- 并发激活去重、取消、失败重试、停用、IDE 退出清理。

### 当前进展

- 已新增 ActivationManager 状态机，支持按 Manifest `onStartup`/`onView` 事件激活、同插件并发去重、失败状态和重试。
- `/plugin-view` 首次打开通过 ActivationManager 等待插件启动，并提供宿主 loading/error/retry 状态；禁用和卸载通过统一停用路径清理运行会话。
- 数据插件保持启动时单次执行语义；没有 `onStartup` 的 UI/service 插件冷启动不再提前启动。
- 已补齐 `onCommand`、`onLanguage` 激活入口：按 ID 从各插件 Manifest 解析候选，只激活声明了该事件且状态为 usable 的插件，并复用同一套去重逻辑。
- `deactivate` 现在对同一插件的并发调用共享同一个停用操作，并先等待仍在进行的激活完成，避免新建会话逃过停用。
- 新增 `deactivateAllForShutdown`：IDE 退出时先等待所有在途激活/停用结束，再统一停止运行时；`window.dart` 的关闭流程已改为走该路径（仍保留 2 秒超时）。
- Python SDK 侧生命周期已串行化：`bridge.py` 用 `asyncio.Lock` 串行化 start/pause/resume/dispose，`inspect.isawaitable` 兼容 sync/async handler，dispose 后 `push` 拒绝新消息；`DataPlugin.on_start` 支持 async `on_contribute`。旧 `on_start/on_pause/on_resume/on_dispose` API 保持可用，协议 Envelope 未改。
- 待完成（归属 T12）：view opened/closed/visibility/focus 事件总线本体。

---

## T12：实现 PluginEventBus 和订阅协议

状态：`[x]`  
依赖：T02、T05、T11

### 目标

为宿主状态变化提供统一、权限受控、可节流的插件事件机制。

### IDE 实现

- 新增 PluginEventBus、SubscriptionRegistry 和 delivery scheduler。
- 实现 subscribe/unsubscribe/emit。
- topic 注册时声明 payload schema、权限和默认投递策略。
- 每个插件使用独立有界事件队列。
- 关键生命周期事件不可静默丢弃；高频事件可 latest/batch。
- session 停止时自动取消全部订阅。
- 支持 `replayLatest`，让晚订阅插件获得当前状态。

### SDK 实现

提供：

```python
subscription = plugin.events.subscribe(
    "editor.document.changed",
    handler,
    filter={"language": "python"},
    delivery="latest",
    debounce_ms=100,
)
subscription.dispose()
```

- 支持 async handler。
- 一个 handler 异常不能终止事件循环。
- 插件 dispose 时自动释放订阅。

### 验收标准

- 插件只能订阅被授权 topic。
- latest/debounce/batch/every 行为符合定义。
- 慢插件不会阻塞宿主或其他插件。
- 旧 session 订阅不会收到新 session 事件。

### 测试

- 订阅、取消、过滤、权限、回放、队列溢出、慢 handler、异常 handler。

---

## T13：实现编辑器文档服务和事件

状态：`[x]`  
依赖：T12

### 目标

为大纲、语言工具和编辑器辅助插件提供宿主级文档能力。

### API

```text
editor.activeDocument.get
editor.document.get
editor.document.symbols
editor.document.reveal
editor.document.selection.get

editor.activeDocument.changed
editor.document.opened
editor.document.changed
editor.document.saved
editor.document.closed
editor.document.selection.changed
```

### IDE 实现

- 为每个文档分配稳定 documentId 和单调 revision。
- document.changed 发送增量 changes，不默认发送完整正文。
- 高频输入默认 debounce/latest。
- `document.symbols` 优先复用 Code Forge 的 LSP `textDocument/documentSymbol`。
- LSP 不可用时提供明确 unavailable 状态；AST fallback 可后续加入。
- reveal 使用 documentId、line、column/range，不让插件直接操作编辑器 controller。

### SDK 实现

- 提供 typed document、symbol、range model。
- 提供订阅和查询封装。
- 处理文档关闭、revision 过期和请求取消。

### 验收标准

- 当前文档切换、输入、保存和关闭事件正确。
- 旧 revision 的符号结果不会覆盖新结果。
- 快速输入会取消/忽略旧 LSP 查询。

### 测试

- 文档生命周期、revision、增量 changes、符号映射、reveal、LSP 取消。

---

## T14：实现运行时检查服务和事件

状态：`[x]`  
依赖：T12

### 目标

提供不依赖 `serial.run_python` 后台轮询的变量和调试状态接口。

### API

```text
runtime.sessions
runtime.state
runtime.scopes
runtime.variables
runtime.children
runtime.objectInfo

runtime.session.created
runtime.session.state.changed
runtime.program.started
runtime.program.paused
runtime.program.resumed
runtime.program.finished
runtime.backend.restarted
runtime.variables.changed
```

### 数据模型

```json
{
  "name": "items",
  "type": "list",
  "repr": "[1, 2, 3]",
  "reference": "runtime-1:generation-4:obj-42",
  "hasChildren": true,
  "namedVariables": 0,
  "indexedVariables": 3
}
```

### IDE 实现

- runtime reference 必须绑定 runtime session/generation。
- backend restart 后所有旧 object reference 失效。
- children 支持 start/count 分页。
- repr、字符串和容器预览设置长度上限。
- 设备运行任务和变量检查共享统一调度器，禁止变量视图擅自发送 CTRL-C。
- 如果当前后端不支持安全检查，返回 capability unavailable，而不是打断程序。

### SDK 实现

- typed RuntimeSession、Scope、Variable、ObjectInfo。
- 懒加载 children。
- 对 stale reference 提供专用异常。

### 验收标准

- 变量查询不会中断正在运行的设备程序。
- paused/finished/restarted 驱动变量刷新。
- 大容器不会一次性返回全部内容。

### 测试

- session/generation、reference 失效、分页、repr 限制、无能力后端、并发运行任务。

---

## T15：实现原生视图 snapshot/patch 协议

状态：`[x]`  
依赖：T01、T05、T11

### 目标

建立与 RFW 无关的视图实例、数据版本和增量更新协议。

### IDE 实现

- ViewInstance 使用 pluginId/sessionId/viewId/instanceId 唯一标识。
- 实现 view.open/snapshot/patch/ack/nack/resync/close。
- patch 事务校验后一次提交。
- revision 不连续时拒绝 patch 并请求 snapshot。
- 关闭视图后拒绝后续 patch。
- 视图状态区分 loading/ready/empty/error/disconnected。

### SDK 实现

- 新增 ViewModelStore。
- 提供 batch context manager 合并 operations。
- 最多一个 in-flight patch；等待期间合并更新。
- nack 或断线重连后发送 snapshot。

### 验收标准

- snapshot 后可以连续应用 insert/update/remove/move。
- 错误 patch 不产生部分状态。
- 丢失 revision 可以自动恢复。
- 多视图实例之间状态不串用。

### 测试

- patch 操作全集、事务回滚、乱序、重复、resync、视图关闭、多个实例。

---

## T16：实现 NativePluginViewRegistry 和通用组件层

状态：`[x]`  
依赖：T08、T15

### 目标

由 Flutter 宿主根据 renderer 类型创建原生视图，并允许插件组合受控的通用组件。

### 第一批 renderer

```text
native.tree
native.virtualList
native.table
native.form
native.markdown
native.log
native.outline
native.variableInspector
```

### 第一批通用组件

```text
布局：Row、Column、Flex、Grid、Wrap、SplitView、Tabs、Section、Toolbar
内容：Text、Icon、Image、Markdown、CodeBlock、Badge
输入：TextField、NumberField、Select、Checkbox、Switch、Slider
操作：Button、IconButton、Menu、ContextMenu、Dropdown、Dialog、Tooltip
数据：VirtualList、TreeView、DataTable、PropertyGrid
```

### IDE 实现

- NativePluginViewRegistry 映射 renderer token 到 Flutter builder。
- PluginViewHost 根据 contribution 创建视图。
- 通用组件 schema 使用稳定抽象，不直接暴露 Flutter constructor。
- 组件属性、事件和版本必须可校验。
- 输入框编辑状态和焦点保留在宿主本地，不逐字符往返 Python 后才显示。
- 对组件深度、节点数量和非法嵌套设置限制。

### 验收标准

- 一个测试插件可以用 Toolbar + SearchField + VirtualList 组成完整页面。
- 未知组件/属性显示可诊断错误边界，不导致整个 IDE 页面崩溃。
- 主题、可访问性、键盘焦点遵循宿主设计。

### 测试

- renderer registry、schema 校验、组件事件、主题切换、错误边界、焦点保持。

---

## T17：实现高性能 VirtualList、TreeView 和 DataTable

状态：`[x]`  
依赖：T15、T16

### 目标

建立大纲、变量、日志、文件树等视图共享的高性能数据基础。

### Tree 数据结构

```text
Map<String, TreeNodeModel> nodeById
Map<String?, List<String>> childrenByParent
Set<String> expandedNodeIds
List<String> visibleNodeIds
```

### IDE 实现

- 使用 `ListView.builder`/Sliver 系列按可见行构建。
- 展开节点只更新受影响的可见区间。
- 未加载节点触发 `requestChildren`。
- 支持选择、键盘导航、展开/折叠、上下文菜单和 loading/error row。
- DataTable 支持虚拟行、稳定列定义、排序事件和分页。
- 避免在每次节点更新时重新 flatten 整棵树；必要时维护增量可见索引。

### 性能门槛

- 10,000 节点快照可加载。
- 100,000 逻辑节点在懒加载下不创建 100,000 个 Widget。
- 单节点 label 更新不重建整个列表。
- 滚动期间不执行 Python RPC。

### 测试

- 10k/100k 数据 benchmark。
- 节点 insert/remove/move、展开、懒加载、selection 保持。
- widget rebuild 计数或等价性能断言。

---

## T18：实现大纲视图端到端样板

状态：`[x]`  
依赖：T09、T11、T13、T17

### 目标

使用真实插件完成 Manifest、导航、激活、事件、LSP symbols、增量树和源码定位全链路。

### 插件行为

- 声明 Python 工具导航容器和 Outline 视图。
- 监听 activeDocument.changed、document.changed、document.saved。
- 请求 `editor.document.symbols(documentId)`。
- 将 DocumentSymbol 映射为稳定树节点 ID。
- 点击节点调用 `editor.document.reveal`。
- 文档切换和内容变化时取消旧请求。

### 宿主行为

- 使用 `native.outline`/`native.tree`。
- 当前文档为空、LSP 不可用、解析中和错误状态完整。
- 视图隐藏时暂停 debounce 后的刷新。

### 验收标准

- 行为达到 Thonny 大纲视图的核心体验。
- 连续输入不会全量重建插件页面。
- 点击类、函数、方法节点能定位到正确位置。
- 快速切换文件不会显示前一个文件的迟到结果。

### 测试

- 符号树映射、稳定 ID、文档切换、迟到请求、reveal、视图可见性。

---

## T19：实现变量检查器端到端样板

状态：`[x]`  
依赖：T09、T11、T14、T17

### 目标

使用真实插件完成 runtime event、scope、变量快照、对象引用和子节点懒加载全链路。

### 插件行为

- 声明 Variables 视图。
- 监听 paused、finished、backend.restarted、variables.changed。
- 查询 scopes 和顶层 variables。
- 展开节点时按 reference 请求 children。
- backend restart 后清理所有本地 reference/cache。

### 宿主行为

- 使用 `native.variableInspector`。
- 支持 globals、locals、nonlocals 分组。
- 显示 name、type、repr，并支持容器展开。
- 容器子项分页加载。
- 运行中且后端不支持安全检查时显示 unavailable，不发送 CTRL-C。

### 验收标准

- 行为达到 Thonny 变量视图的核心浏览能力。
- 后台变量刷新不会打断用户程序。
- 旧 reference 不会访问新 runtime session 对象。
- 大列表和字典按页加载。

### 测试

- scopes、懒加载、分页、stale reference、backend restart、视图隐藏、超长 repr。

---

## T20：实现命令、菜单、配置和 when 上下文

状态：`[x]`  
依赖：T08、T11、T12、T16

### 目标

让复杂插件不必把所有操作做成视图内文本按钮。

### IDE 实现

- CommandRegistry 注册、执行、权限检查和可用状态。
- MenuRegistry 支持 view/title、view/context、navigation/context 等位置。
- ConfigurationRegistry 生成设置项并持久化。
- 配置变化通过事件总线发送。
- when/context key 控制导航、命令和菜单可见/可用状态。
- 使用宿主图标和 tooltip，保持桌面/移动交互一致。

### SDK 实现

- command handler 注册和自动清理。
- configuration get/update/changed。
- 上下文菜单事件携带 view/node/selection 上下文。

### 验收标准

- 变量视图刷新命令可出现在标题工具栏和上下文菜单。
- 配置修改后无需重启插件即可生效。
- 不可用命令正确 disabled，而不是点击后才失败。

### 测试

- 命令冲突、when 更新、权限拒绝、配置持久化、菜单上下文。

### 完成记录

- 新增 `ContextKeyHost` 从 editor/runtime/device/workspace/view 事件生产 context key；`MenuResolver` 按 location/view/when 解析菜单，命令 `when` 控制 enabled。
- 新增 `CommandService`：按贡献查找命令、`activateForCommand`/已有会话后发送 `ide.command.execute`；SDK `Commands.register` 本地分发，dispose 自动清理。
- 新增 `PluginConfigStore` + `sdk.configuration.get/set/list`，持久化到插件 `data/configuration.json`，经事件总线发出 `configuration.changed`；详情页可编辑布尔配置。
- `view/title` 合并进原生 AppBar，`view/context` 合并进右键菜单，`navigation/context` 挂在导航图标上；动态 `appBarAction` 仍可用。
- `debug-enhanced` 升至 1.6.0：声明 `refreshVariables` 命令与 title/context 菜单、`showPrivate` 配置；去掉仅用于刷新的动态 AppBar/上下文动作。
- 验证：IDE MenuResolver/ConfigStore/协议夹具与插件页 10 项通过；SDK commands + device variables + outline/packager 定向通过；scoped analyzer 无问题。

---

## T21：实现背压、批处理、取消和性能预算

状态：`[x]`  
依赖：T05、T12、T15、T17

### 目标

保证慢插件、高频事件和大 patch 不拖垮 Flutter UI 或单例 Python runtime。

### 实现内容

- 每插件 control queue 和 view patch queue 有明确容量。
- 请求支持 deadline 和 cancellation。
- 文档变化、selection、serial data 使用 topic 默认合并策略。
- view patch 保持最多一个 in-flight revision。
- 队列高水位记录指标并触发降级。
- 小消息批量发送；大 payload 预留独立 data channel。
- JSON 作为第一阶段编码；通过指标决定是否切换 MessagePack。
- 大消息解析不得长时间阻塞 Flutter UI isolate，必要时移动到工作 isolate。
- 不可见视图暂停非关键刷新。
- 对 snapshot、patch、节点数、repr、日志批次设置大小限制。

### 初始预算建议

```text
普通 RPC 默认超时：5 s
UI 交互 RPC 默认超时：2 s
一个视图最多一个 in-flight patch
document.changed 默认 debounce：100 ms
selection.changed 默认 latest/throttle：50 ms
serial.data.received 默认 batch：16-50 ms
```

具体数值应通过 benchmark 调整并记录。

### 验收标准

- 慢插件不会阻塞其他插件消息处理。
- 事件风暴下队列有界，内存不会持续增长。
- 过期请求和 patch 可以取消或丢弃。
- 用户滚动和输入期间保持可接受帧率。

### 测试

- 每秒 1,000 条小消息。
- 慢 handler、永不响应 handler、持续 patch、serial burst。
- 内存和队列深度压力测试。

### 完成记录

- `PluginRunManager` 为每个插件会话建立容量明确的 control queue（256）和 view patch queue（32），统一调度两个队首并按全局 `sequence` 顺序分批处理（每批 32 条）；control 满时拒绝新请求，patch 满时丢弃最旧请求并返回 `backpressure`，队列深度/高水位/丢弃计入 session metrics。
- 普通 RPC 默认 5 秒、UI RPC 默认 2 秒；IDE 等待型请求写入绝对 `deadline`，超时自动发送 `ide.request.cancel`，迟到回复按有界取消历史丢弃。SDK Envelope 支持可选 deadline，过期请求执行前返回 `timeout`；生命周期、命令和动态上下文菜单使用可取消 asyncio task，取消帧不会阻塞接收循环。
- 小消息在 IDE inbound 和 SDK outbound 均按 32 条批次 drain 并主动归还事件循环；单 envelope 上限 8 MiB，超过 256 KiB 的 JSON 在 Flutter worker isolate 解析，`data` 字段保留为后续独立 data channel，不在 latency-sensitive control 路径扩展 MessagePack。
- View snapshot 限制 20,000 nodes，patch 限制 2,000 ops，单 View payload 限制 2 MiB；patch 后节点总数同样受限。SDK 保持单 in-flight patch并自动拆分超限事务；不可见 View 只更新本地镜像，恢复可见时发送完整 snapshot。runtime repr 继续使用既有 1,024 字符限制，日志按 UTF-8 64 KiB 分块，IDE 侧再次截断防御。
- `editor.document.changed` 默认 debounce 100 ms、`editor.document.selection.changed` 默认 throttle/latest 50 ms、`serial.data.received` 默认 batch 32 ms；事件订阅队列继续有界并记录 overflow/high-water。
- 验证：IDE scoped analyzer 无问题；T21/相关 Dart 回归 63 项通过，`plugin_run_manager_test.dart` 15 项通过（含 1,000 小消息、control/patch 混排、畸形 sequence、超时取消和 300 KiB isolate 解码）。SDK T21/协议/View/输出定向 44 项通过，compileall 通过；全量 303 项仍为既有 RFW/UI 基线 4 failures + 5 errors，无 T21 新增失败。两仓库 deadline/cancel fixture 结构一致，diff check 仅 LF/CRLF 提示。
- 初始预算已按上述测试固定，真实低端 Android/桌面设备的 frame-time 与常驻内存仍需后续 benchmark 调整数值；这只影响预算调优，不改变 T21 协议或有界降级行为。T22 未开始。

---

## T22：实现插件监控、故障恢复和诊断

状态：`[x]`  
依赖：T06、T11、T21

### 目标

在共享解释器边界内提供可观察、可恢复的运行体验。

### 指标

```text
插件状态和激活耗时
发送/接收消息数和字节数
事件/patch 队列深度
RPC p50/p95 延迟
超时、取消、丢弃和错误数
最近错误和 traceback
视图 revision/resync 次数
runtime generation 和重启次数
```

### IDE 实现

- 将指标加入插件监视页和详情页。
- 插件 handler 连续失败时暂停对应订阅或视图更新。
- 插件协作式停止失败时提供“重启 Python runtime”。
- runtime 重启前关闭所有 session，重启后按需重新激活可见插件。
- 增加指数退避，避免故障插件无限重启。
- 输出日志按 pluginId/sessionId 分流。

### SDK 实现

- 未捕获 callback/task 异常统一上报。
- 提供 health/ping 响应。
- dispose 尽最大努力取消任务并注销 bridge handler。

### 验收标准

- 可以定位哪个插件产生延迟、队列积压或错误。
- 一个插件 Python 异常不会终止其他插件事件循环。
- runtime 整体重启后 UI 不保留旧 session 状态。
- native extension 崩溃仍属于已知无法隔离边界，文档明确说明。

### 测试

- callback 异常、任务异常、超时风暴、无法停止、runtime 重启、故障循环熔断。

### 完成记录

- `PluginRunManager` 会话已接入 `PluginMetricsRegistry`，实时记录状态、激活耗时、消息/字节、事件/control/patch 队列深度和高水位、RPC p50/p95、timeout/cancel/drop/error、最近错误/traceback、View patch/resync、health latency；插件详情页显示当前/最后会话诊断，监控页新增运行状态、按 pluginId/sessionId 过滤的输出和原权限日志三个 Tab。
- IDE 提供 `ping`、恢复投递、重启插件和重启 Python runtime 操作。连续 8 次失败后暂停该插件事件和 patch 投递；暂停期间 SDK 仅维护本地 View 模型，恢复时 IDE 对该插件全部活动 View 发送 resync，由 snapshot 重新收敛。启动/意外退出失败接入 1s 到 60s 指数退避，避免故障插件无限重启。
- `IdeOutputEntry` 增加可选 `pluginId`/`sessionId`，插件启动、运行和错误输出均按真实 session 分流。普通停止保留最后诊断；协作式停止超时标记 failed/stopTimedOut，单插件重复启动仍拒绝并发 Python target，用户执行 runtime 整体重启时强制脱离残留 target、清空旧 event/View/component/session 状态，并只恢复当前可见插件及 `onStartup` service。
- SDK Bridge 响应 `ide.health.ping`，返回 active request task 和 pending response 数；event/page/view/command callback、request task 和 asyncio loop 未捕获异常统一以 `sdk.runtime.report_error` 上报且不终止其他插件事件循环。dispose 最佳努力取消 request task、失败 pending callback，清空 events/commands/views/callback binding，并由 transport close 注销 native bridge handler。
- 验证：IDE scoped analyzer 无问题；T22 manager/metrics/runtime/output/store 组合 44 项及 event/View/插件页面组合 40 项通过。SDK health/recovery/event/pending/transport/View/command 定向 66 项通过，compileall 通过；全量 308 项仍仅为既有 RFW/UI 基线 4 failures + 5 errors，无 T22 新增失败。`git diff --check` 无空白错误，仅行尾转换提示。
- 已知边界：Python 级异常、卡死协作式停止和共享 runtime 状态可以诊断/恢复；native extension 导致的进程级崩溃仍无法在同一解释器/进程内隔离，必须依赖未来进程级插件宿主。

---

## T23：删除 RFW 和旧插件能力

状态：`[x]`  
依赖：T16、T18、T19、T20

### 目标

完成破坏式切换，只保留原生 Flutter 插件视图和当前协议/Manifest。

### 实现内容

- 删除 `/plugins/body`、`PluginBody`、RemoteWidget/DynamicContent 和插件 RFW runtime。
- 删除 SDK RFW 页面、组件、router 和序列化 API，以及对应示例、fixture 和文档。
- 删除 compatibility adapter、legacy contribution、旧协议字段别名和旧 Manifest 解析路径。
- 内置/示例插件全部改用 Manifest v2 和 native renderer。
- 检测到旧插件数据时标记为不可用，不加载或自动转换插件代码。

### 验收标准

- IDE 和 SDK 不再包含插件 RFW 执行路径。
- 插件模板只生成 Manifest v2 和 native view。
- 大纲和变量示例完全不依赖 RFW。
- 旧插件得到稳定的“不支持版本”错误，不进入运行时。

### 测试

- 旧协议/Manifest/RFW 插件拒绝测试。
- 删除后无 RFW import、路由、renderer token 或 SDK 导出。

### 完成记录

- IDE：删除 `lib/pages/plugins/widgets/` 全部 RFW 组件（button/display/markdown/media/rfw_lib/selection/text_field），插件列表不再打开旧插件 UI、详情页不渲染 RemoteWidget/DynamicContent；`lib/features/plugin_view/` 的 `Video` 组件由原 RFW 耦合的 `RfwVideoPlayer` 改为原生 `PluginVideoPlayer`（`video_player` 直驱，保留 play/pause/seek/volume/speed/loop/fullscreen 的 `VideoController` 契约，无任何 RFW import），对应测试同步改为断言 `PluginVideoPlayer`。路由仅保留 `/plugins` 插件管理页。
- SDK：删除 `src/pyrite_sdk/api/ui/`（`__init__`、context_manager/event/page/router、sentence/、widgets/）、`interfaces/ui.py`、`utils/ui.py`、`utils/rfw_formatter.py` 及 `tools/utils/rfw_formatter.py`；删除 `docs/api/websockets.md` 和 `file_counter_plugin`/`markdown_plugin`/`normal_plugin`/`ui_plugin` 示例；其余示例与 `src/tools/template/` 全部为 Manifest v2 + native renderer（`native.form` 等）。
- 旧插件拒绝：IDE 与 SDK Manifest 校验均保留 `rfwRendererUnsupported` 稳定错误码，`renderer = "rfw"`/`rfw.*` 直接拒绝、不进入运行时；测试覆盖旧协议/Manifest/RFW 拒绝（`plugin_manifest_validator_test`、`test_manifest_v2`、`test_packager_runtime` 的 `rfw_renderer.toml` 夹具等）。
- 删除面核验：IDE `lib/`+`test/` 与 SDK `src/`+`tests/`+`examples/`+`docs/` 已用 `Select-String` 全量扫描，无残留 RFW import/路由/renderer token/SDK 导出（仅保留上述拒绝路径文案）；assets 命中均为二进制字体/图片误报。
- 验证：IDE scoped analyzer 零问题；`test/core/sdk`+`test/pages/plugins` 串行 335 项全通过，`test/features/plugin_view/component_builder_test.dart` 28 项通过。SDK 全量 `unittest` 266 项 OK（原既有 RFW/UI 基线 4 failures + 5 errors 随删除一并消失）。IDE 全量 `flutter test` 剩余 10 项失败全部位于未修改的既有文件（git/ui_utils/raw_paste/widget 环境类问题，与 T23 无关）。两仓库 `git diff --check` 仅行尾转换提示，无空白错误。

---

## T24：四平台验证、文档和发布门槛

状态：`[x]`（Linux/macOS 发布构建与平台矩阵保持 `[!]`，需在对应实际 runner/CI 执行）
依赖：T00-T23 全部完成

### 目标

确认重构在 Windows、Linux、macOS、Android 上符合统一协议和用户体验。

### 平台矩阵

| 场景 | Windows | Linux | macOS | Android |
|---|---:|---:|---:|---:|
| PythonBridge 握手 | 必测 | 必测 | 必测 | 必测 |
| 多插件同时活动 | 必测 | 必测 | 必测 | 必测 |
| 导航栏/Drawer | 必测 | 必测 | 必测 | 必测 |
| 大纲视图 | 必测 | 必测 | 必测 | 必测 |
| 变量视图 | 必测 | 必测 | 必测 | 必测 |
| 插件启停与清理 | 必测 | 必测 | 必测 | 必测 |
| runtime 整体重启 | 必测 | 必测 | 必测 | 必测 |
| 后台/恢复 | 记录 | 记录 | 必测 | 必测 |
| 10k 节点性能 | 必测 | 必测 | 必测 | 必测 |
| 发布构建 | 必测 | 必测 | 必测 | APK/AAB 必测 |

### 必须更新的文档

- 插件 Manifest v2。
- contribution points。
- activation events。
- event topics 和权限。
- native view/component catalog。
- snapshot/patch 协议。
- PythonBridge transport 和线程规则。
- 单例解释器共享状态与插件开发限制。
- 大纲、变量示例插件。
- 破坏性升级说明和当前插件开发指南。

### 最终验证命令

```text
dart format .
flutter analyze --no-fatal-infos lib test
flutter test
SDK 仓库完整测试
flutter build windows --release
flutter build linux --release
flutter build macos --release
flutter build apk --release
```

无法在当前主机执行的平台，必须在 CI 或对应平台设备执行，并记录构建和运行结果。

### 验收标准

- 四平台协议 fixture 一致。
- 插件安装、导航、激活、事件、原生 UI 和停用完成端到端验证。
- 插件系统不存在 WebSocket 传输代码或依赖。
- 插件系统不存在 RFW 运行路径或 SDK API。
- 已知共享解释器边界在开发文档和用户诊断界面中明确呈现。

## 11. 最终 Definition of Done

只有同时满足以下条件，本轮重构才算完成：

- [ ] UI 插件必须通过 Manifest 注册导航容器。
- [ ] 桌面 NavigationRail 和移动 NavigationDrawer 使用同一注册表。
- [ ] 插件中心列表项进入详情页。
- [ ] 插件按 activation event 延迟启动。
- [ ] 本地正式通信使用 PythonBridge。
- [ ] 插件通信代码中不存在 WebSocket transport 或 fallback。
- [ ] 所有消息使用协议 v1 和 session/generation 校验。
- [ ] 权限默认拒绝，多插件上下文不会串用。
- [ ] 插件事件总线支持订阅、取消、权限、过滤和背压。
- [ ] 编辑器文档服务可以支持大纲视图。
- [ ] 运行时检查服务可以安全支持变量视图。
- [ ] 原生视图支持 snapshot、patch、revision 和 resync。
- [ ] Tree/List/Table 使用虚拟化和稳定 ID。
- [ ] 大纲视图完成端到端实现。
- [ ] 变量视图完成端到端实现，且不通过 `serial.run_python` 后台打断设备。
- [ ] 插件监视页可查看延迟、队列、错误和 runtime generation。
- [x] RFW 插件运行路径和兼容层已删除，旧插件被明确拒绝。
- [ ] Windows、Linux、macOS、Android 完成平台矩阵验证。

## 12. 实施记录

任务：T00  
提交：工作区未提交  
IDE 修改：新增协议/插件 fixture，补充 PluginRunManager、Manifest、插件列表/详情/RFW 基线测试。  
SDK 修改：新增协议 fixture、Bridge request/response/callback 测试和真实最小插件生命周期测试。  
协议变更：无，固定当前 v0 WebSocket Envelope。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；`python -m unittest tests.test_protocol_fixtures -v`。  
验证结果：IDE 49 tests 通过；SDK 新增 4 tests 通过；SDK 全量测试存在 9 个既有失败/错误，已记录为偏差。  
偏差/后续事项：T01 开始前先确认是否接受这些既有 SDK 基线失败作为已知问题。

任务：T01  
提交：工作区未提交  
IDE 修改：新增严格协议 v1 校验器，将 PluginRunManager 接入四阶段握手、能力协商、会话/代次/序列校验、请求超时及重复响应防护，并补充协议和回归测试。  
SDK 修改：Envelope 改为 v1 camelCase 线格式，Bridge 接入同形握手、严格校验和 protocol_error，同时保留 Python 侧旧属性兼容并扩展真实子进程生命周期测试。  
协议变更：线上 Envelope 从 v0 升级到 v1；新增 `pluginId/sessionId/generation/sequence` 和初始化握手，WebSocket 仅作为当前传输，尚未开始 T03 transport 抽象。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；`flutter analyze --no-fatal-infos lib/core/sdk test/core/sdk test/pages/plugins`；SDK 定向测试、影响测试及 `python -m unittest discover -s tests -v`；`python -m py_compile ...`；两仓库 `git diff --check`。  
验证结果：IDE 回归 52 tests、Dart T01 定向 17 tests、SDK T01 5 tests、SDK callback/dispose 4 tests 均通过；analyzer 和 Python 语法检查通过；协议夹具哈希一致。  
偏差/后续事项：SDK 全量仍有 T00 已确认的 4 failures、5 errors，未出现 T01 新回归；T02 保持未开始。

任务：T02  
提交：工作区未提交  
IDE 修改：权限默认策略改为 fail-closed，补齐 command 权限表和三态审计；API provider 全部去除最近绑定 manager 状态，handler 使用所属插件上下文，并修复 read/write 权限继承方向。  
SDK 修改：新增 API 错误异常体系和权限文档，Bridge 将 `permission_denied`、`unknown_command` 等错误响应转换为专用异常。  
协议变更：SDK 错误 payload 固定使用 `code/message/details`；新增 `permission_denied`、`unknown_command`、`invalid_context` 错误码，Envelope v1 结构不变。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；`flutter analyze --no-fatal-infos lib/core/sdk lib/pages/plugins test/core/sdk test/pages/plugins`；`python -m unittest tests.test_permission_errors tests.test_protocol_fixtures -v`；`python -m unittest discover -s tests -v`；Python `py_compile`；两仓库 `git diff --check`。  
验证结果：IDE 57 tests 通过且 analyzer 零问题；SDK 定向 7 tests 通过；SDK 全量 87 tests 中仍为既有 4 failures、5 errors，无新增回归。  
偏差/后续事项：T03 尚未开始；当前仍使用 WebSocket，transport 抽象属于下一任务。

任务：T03  
提交：工作区未提交  
IDE 修改：新增 `PluginTransport` 状态/字节流接口和 `WebSocketPluginTransport`；`PluginRunManager` 改为 transport 注入，并统一处理 transport 状态、错误、挂起请求与幂等关闭。  
SDK 修改：新增 `Transport` ABC、状态和关闭异常，WebSocket 服务与连接收发迁移到 `WebSocketTransport`；`Bridge` 业务 handler 仅依赖 transport。  
协议变更：无；继续使用协议 v1 JSON Envelope，WebSocket 仍是当前默认兼容 transport。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；`flutter analyze --no-fatal-infos lib/core/sdk lib/pages/plugins test/core/sdk test/pages/plugins`；SDK transport/fixture/permission/dispose 定向测试；`python -m unittest discover -s tests -v`；Python `py_compile`；两仓库 `git diff --check`。  
验证结果：IDE 59 tests 通过且 analyzer 零问题；SDK 定向 14 tests 通过；SDK 全量 90 tests 中仍为既有 4 failures、5 errors，无新增回归。  
偏差/后续事项：正式运行仍使用 WebSocket；PythonBridge 适配属于 T04，本任务未开始 T04。

任务：T04  
提交：工作区未提交  
IDE 修改：新增 `PythonBridgePluginTransport` 和真实 runner 集成测试；提供 native port/channel label 启动上下文、有限发送重试、deadline、状态传播及幂等关闭。  
SDK 修改：新增 `DartBridgeTransport`，通过 `dart_bridge` 注册有界队列入口、发送 bytes、注销 handler，并支持 Dart VM session restart 后按 label 重绑 port。  
协议变更：无；继续使用协议 v1 Envelope。本任务未切换生产默认 transport，也未删除 WebSocket，相关破坏式切换仍属于 T05。  
验证命令：IDE transport/插件/持久化回归测试、T04 单元测试、定向 analyzer；SDK transport/协议/权限定向测试、全量测试和 Python 语法检查；`flutter test -d windows integration_test/python_bridge_plugin_transport_test.dart`；`flutter test -d 19f50d8e integration_test/python_bridge_plugin_transport_test.dart`；两仓库 `git diff --check`。  
验证结果：IDE 既有回归 65 tests 通过，T04 单元测试 7 tests 通过且 analyzer 零问题；SDK T04 7 tests、定向 21 tests 通过；SDK 全量 97 tests 仍为既有 4 failures、5 errors，无新增回归；Windows 与 Android 16 arm64 真机集成测试均通过三个真实 channel 的 0 B 至 1 MB 双向往返。  
偏差/后续事项：当前主机没有 Linux/macOS 实际 runner，四平台验收尚缺两项，因此 T04 保持阻塞；项目负责人已指示先行实施 T05，T04 仍需在对应实际 runner 上执行同一集成测试，或明确修改验收范围。

任务：T05  
提交：工作区未提交  
IDE 修改：正式启动路径切换为 `PythonBridgePluginTransport`，移除插件 WebSocket/free-port/localhost 重试路径和 `freeport` 依赖；详情与监视 UI 显示 transport 类型。  
SDK 修改：`Bridge` 默认只构造 `DartBridgeTransport`，删除 `WebSocketTransport`、`websockets` 依赖和 WebSocket 文档；缺失/非法 native 上下文或旧 TCP port 环境直接失败。  
协议变更：无；继续使用协议 v1 Envelope。transport 启动方式为破坏式切换，不提供旧 TCP/WebSocket fallback 或兼容入口。  
验证命令：IDE 插件回归测试与 analyzer；SDK transport/协议/权限/生命周期定向测试、全量测试、Python 编译检查和 `uv lock --check`；Windows 与 Android 16 arm64 PythonBridge 集成测试；旧入口扫描和两仓库 `git diff --check`。  
验证结果：IDE 66 tests、SDK T05 定向 20 tests 通过；analyzer 无 error/warning（60 条既有 info）；SDK 全量 97 tests 仍为既有 4 failures、5 errors；Windows 与 Android 实机三通道集成测试通过，依赖锁和 diff 检查通过。  
偏差/后续事项：当前没有 Linux/macOS 实际 runner，四平台 smoke 尚缺两项，因此 T05 标记为阻塞；实现和当前可用平台验证已完成，未开始 T06。

任务：T06  
提交：工作区未提交  
IDE 修改：新增单例 `PythonRuntimeHost` 和显式 `PluginSession`，集中管理 runtime/plugin start、stop、restart、generation、启动锁、取消和失败清理；移除插件启动对 `Directory.current` 的修改；为每个 session 提供 cache 下的独立临时目录；生命周期回调等待 SDK 应答；未退出的失败 target、连续 runtime restart 和旧 session 高序消息均有隔离保护。`python_runtime` 的共享 dispatcher 增加可重试启动、活跃 target/reset 屏障、环境恢复和基础 SDK 模块保留；dispatcher 命令和 completion 使用 Dart runtime epoch 与 native port 联合校验，旧 VM 的同号 completion 不能完成新 VM 请求。run/reset 使用单一有序命令流，保留连续 run 的并发，同时保证 reset 的提交顺序。所有 native session signal 还携带同一 Dart VM 内稳定的 session token。  
SDK 修改：新增不可变 `PluginContext` 并通过 `Bridge.context`、`BasePlugin.context` 暴露；Path API 使用捕获的上下文；`BridgeOutputRouter` 在线程、Bridge 和 transport 退出时注销路由与残留 buffer；SDK 侧旧 session 消息不再推进当前 sequence 水位。`DartBridgeTransport` 捕获 Dart session token：同一 token 继续支持精确 label 的 port 重绑，token 变化时关闭旧 transport/Bridge，使新宿主使用全新的握手、sequence 和 PluginContext。出站请求在队列满、loop/transport 关闭和 native send 失败时会完成并清理 callback；同步路径请求改为按 requestId 关联并在超时后注销。  
协议变更：继续使用插件协议 v1；host-managed handshake 要求并校验完整 `pluginContext`（plugin/session/generation/绝对路径/capabilities），旧 session/generation 消息被丢弃且不能污染当前 sequence。runtime dispatcher 的内部控制消息新增 `runtimeEpoch/runtimePort`，completion 回显 `runtimeEpoch`；该字段不进入插件 Envelope。Dart 出站规范化会替换 legacy responder 产生的空 requestId，禁止在线上发送无效协议 v1 Envelope。  
验证命令：IDE 插件回归和定向 analyzer；`flutter test -d windows integration_test/python_bridge_plugin_transport_test.dart`；runtime platform-interface analyzer 和嵌入 Python 编译；SDK context/path/transport/protocol/permission/output-router 定向测试、全量测试、`compileall`、`uv lock --check`；三个工作树 `git diff --check`。  
验证结果：IDE/runtime 回归 80 tests 通过；analyzer 无 error/warning（仅 60 条既有 info）；runtime epoch 2 tests、SDK Dart-session recovery、pending response/path concurrency 和 native send failure 定向测试通过。Windows 真实嵌入式 CPython 三 channel 的 0 B 至 1 MB 双向往返、soft reset，以及 `run A -> reset R1 -> run B -> reset R2` 有序完成均通过。SDK 全量 122 tests 仍为既有 4 failures、5 errors，没有新增回归；Python 编译、依赖锁和 diff 检查通过。  
偏差/后续事项：`restartRuntime()` 明确定义为同一 CPython 解释器内的 soft reset，不宣称 finalize/recreate。Dart VM token 变化后的旧 Bridge 清理已用 fake native bridge 验证，但当前主机无法真实重建 Android Flutter engine 并保留同一进程，因此仍需在 Android 前后台/engine 重建场景实测；Linux/macOS 仍无实际 runner。

任务：T07  
提交：工作区未提交  
IDE 修改：新增严格的 Manifest v2 Dart model、TOML 解析器、标准化 JSON 持久化和稳定错误码，覆盖 navigation containers、views、commands、menus、configuration、activation events、细粒度权限、renderer/icon/when 与全局 ID 冲突。安装、启用、pending update、冷启动和 active-backup recovery 均校验 Manifest v2；冲突或无效插件被禁用且不能从缓存页面执行。持久化权限 grant 受 manifest 声明约束，插件 ID 同时拒绝大小写别名和 Windows 保留路径名。配置值要求可 JSON round-trip、int64 有界且 enum 类型严格；`when` 解析限制长度、token 数和递归深度。  
SDK 修改：新增 Pydantic Manifest v2 model、严格 TOML loader、validator 和安全默认的 builder，并由 `pyrsdk package`/测试入口复用；三个模板与八个示例迁移到 Manifest v2 和最小权限，`pyrsdk create` 使用 `shutil.copy2` 且拒绝覆盖已有文件。更新权限文档，wheel 包含三个模板的 `requirements.txt`；IDE/SDK 共享 14 个 golden fixture。  
协议变更：插件 Envelope 仍为协议 v1，没有 wire 结构变化；插件元数据仅接受 `manifest_version = 2` 和 `protocol_version = 1`。v1/缺版本 Manifest、RFW renderer、未知 renderer、非法 `when`、缺导航 UI 及贡献冲突均以稳定 manifest 错误码拒绝。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；T07 定向及全量 `flutter analyze --no-fatal-infos`；SDK Manifest/CLI/packager 定向测试与 `python -m unittest discover -s tests -v`；`python -m compileall -q src`；`uv lock --check`；Dart 格式检查、fixture 目录 byte diff、IDE/SDK/`python_runtime` 三个工作树 `git diff --check`；SDK wheel 构建及模板内容检查。  
验证结果：IDE 插件回归 114 tests 全部通过；T07 定向 analyzer 无问题，全量 analyzer 无 error/warning（60 条既有 info），7 个 Dart 文件格式检查无变化。SDK 定向 49 tests 全部通过；SDK 全量 138 tests 中 129 通过，仍为既有 4 failures、5 errors。两端各 14 个 fixture 内容一致；Python 编译、依赖锁、wheel 模板内容和三个工作树 diff 检查通过。  
偏差/后续事项：SDK 全量的 4 failures、5 errors 仍来自 T00 已记录的缺失 `ai_plugin`、`SizedBox` 可选尺寸、旧 callback 名称和 RFW 示例断言，不属于 T07 回归。RFW runtime/API 的实际删除仍属于 T23；T08 已完成。

任务：T08  
提交：工作区未提交  
IDE 修改：新增受限 `WhenExpression`、`ContextKeyService` 和 `ContributionRegistry`，提供 Navigation/View/Command/Menu/Configuration 子注册表、按插件原子注册/替换/注销、context key 增量可见性更新和失败回滚；插件管理器接入冷启动、安装、更新、启用、禁用和卸载生命周期。  
SDK 修改：无。  
协议变更：无；贡献定义继续来自 Manifest v2，`when` 只允许受限 context key 表达式。  
验证命令：`flutter test test/core/sdk test/pages/plugins test/core/services/persistence/plugin_toml_parser_test.dart`；`flutter analyze --no-fatal-infos lib/core/sdk lib/pages/plugins test/core/sdk test/pages/plugins`；Dart format、`git diff --check`。  
验证结果：scoped analyzer 无问题；scoped 测试 119 项全部通过；新增 T08 定向测试覆盖重复 ID、失败回滚、增量更新和禁用/卸载清理。  
偏差/后续事项：T09 已完成；Linux/macOS 和既有 SDK 全量历史问题不属于本任务验证范围。

任务：T09  
提交：工作区未提交  
IDE 修改：将动态插件导航容器合并到桌面 NavigationRail、平板 Rail 和移动 NavigationDrawer，按稳定顺序生成入口；新增宿主 `/plugin-view` 路由、icon token fallback、跨设备索引同步和当前入口删除后的文件页回退。  
SDK 修改：无。  
协议变更：无。  
验证命令：`flutter test test/features/function_page_navigation_test.dart test/pages/plugins`；`flutter analyze --no-fatal-infos lib/features/function_page.dart lib/app/routes.dart lib/pages/plugins/main.dart test/features/function_page_navigation_test.dart`；Dart format、`git diff --check`。  
验证结果：NavigationRail/NavigationDrawer 动态入口 widget test 和插件页面回归 3 项全部通过；scoped analyzer 无 error/warning；格式化和 diff 检查通过。  
偏差/后续事项：T10 尚未开始。

任务：T10  
提交：工作区未提交  
IDE 修改：新增 `/plugins/detail?id=...` 路由和 `PluginDetailPage`（`lib/pages/plugins/detail.dart`），展示版本、作者、类型、状态、运行状态、激活状态与错误、声明权限（按 resource 分组、action 排序）及来自 ContributionRegistry 的导航/视图/命令贡献；提供打开、启用、停用、启动/停止（service）、重启、卸载（带确认对话框）操作，“打开”经 ActivationManager 激活后路由到宿主 `/plugin-view`。插件中心列表项点击（`lib/pages/plugins/main.dart`）和 PopupMenu 的 details 动作改为进入详情页，不再直接打开插件 UI；`lib/app/routes.dart` 注册详情路由。非 UI 或缺导航容器的插件不显示无效“打开”按钮，插件不存在时显示缺失提示而非崩溃。  
SDK 修改：无。  
协议变更：无。  
验证命令：`flutter test test/pages/plugins`；`flutter analyze --no-fatal-infos lib/pages/plugins/detail.dart lib/pages/plugins/main.dart lib/app/routes.dart test/pages/plugins`。  
验证结果：8 项 widget test 全部通过（列表项进入详情页而非插件 UI、详情元数据/贡献渲染、缺失插件提示、details 菜单进入详情页、停用切换、删除确认、打开路由到 `/plugin-view`、禁用插件忽略缓存运行页）；scoped analyzer 无问题。  
偏差/后续事项：RFW `/plugins/body` 与 `PluginBody` 的实际删除仍归属 T23，本任务保留旧路由仅用于回归对照；T11 已完成。

任务：T11  
提交：工作区未提交  
IDE 修改：新增 `ActivationManager` 激活状态机，覆盖 `onStartup`/`onView` 事件激活、同插件并发去重、失败状态与重试；补齐 `activateForView`/`activateForCommand`/`activateForLanguage` 三个入口，命令与语言按 ID 从各插件 Manifest 解析候选并只激活声明该事件且状态为 usable 的插件；`deactivate` 对同一插件的并发调用共享同一停用操作，并先等待在途激活收敛；新增 `deactivateAllForShutdown`，退出时等待所有在途激活/停用后再统一停止运行时，`window.dart` 关闭流程改走该路径（保留 2 秒超时）；`/plugin-view` 首次打开经 ActivationManager 等待启动并提供 loading/error/retry，禁用与卸载走统一停用路径清理运行会话。  
SDK 修改：`bridge.py` 用 `asyncio.Lock` 串行化 start/pause/resume/dispose，`inspect.isawaitable` 兼容 sync/async handler，dispose 后 `push` 拒绝新消息；`DataPlugin.on_start` 支持 async `on_contribute`；旧 `on_start/on_pause/on_resume/on_dispose` API 保持可用。  
协议变更：无；Envelope v1 结构不变。  
验证命令：`flutter test test/core/sdk/activation_manager_test.dart`；`flutter test test/core/sdk test/pages/plugins test/features`；`flutter analyze --no-fatal-infos lib/core/sdk/activation_manager.dart lib/features/window.dart lib/pages/plugins/main.dart lib/core/sdk/plugin_manager_provider.dart test/core/sdk/activation_manager_test.dart`；SDK pytest 全量；`dart format`；两仓库 `git diff --check`。  
验证结果：激活测试由 3 项扩到 8 项全部通过（新增覆盖 onCommand 选择性激活、onLanguage 多插件激活、停用等待在途激活、并发停用去重、退出前等待）；scoped 回归 110 tests 通过；scoped analyzer 零问题；SDK pytest 套件退出码 0；格式化幂等、diff 检查通过。  
偏差/后续事项：view opened/closed/visibility/focus 事件总线本体按任务划分归属 T12，本任务未扩大范围；T10 仍未开始。`dart format --output=none` 只报告不写入，新建文件为 LF 而仓库为 CRLF 时会持续报 changed，需用不带该参数的 `dart format` 写入。

任务：T12  
提交：工作区未提交  
IDE 修改：新增 `plugin_event_bus.dart`（`PluginEventBus`、`EventTopicRegistry`、`_Subscription` 投递调度器），主题闭集默认拒绝，按 topic 声明所需权限、默认投递策略和 replayLatest；实现 every/latest/batch/debounce/throttle 五种投递，每订阅有界队列（`every` 溢出标记、coalescing 模式丢旧），订阅键为 plugin+session+subscriptionId。新增 `plugin_event_bus_provider.dart`：宿主级单例，`deliver` 仅在 plugin/session/generation 全部匹配时经该会话 `PluginRunManager` 投递。新增 `api/events_api.dart`（`SdkEvents`）绑定 `sdk.events.subscribe`/`sdk.events.unsubscribe` handler，使用 run manager 已校验的 plugin/session 身份向总线注册。`PluginRunManager` 新增 `ide.event.emit` 常量与 `sendEvent`（fire-and-forget，握手未完成不投递）。`permissions.dart` 将订阅/退订登记为 public（总线内部按 topic 校验权限）。run manager provider 在 stop/意外退出/runtime 重启/退出时清理对应 session 订阅并在重启时清空 replay。`PluginViewHost` 在 open/focus/close 发出 `view.*` 生命周期事件（补齐 T11 遗留）。  
SDK 修改：新增 `api/events.py`（`PluginEventBus`、`Subscription`），`plugin.events.subscribe(topic, handler, filter=, delivery=, debounce_ms=)` 返回可 `dispose()` 的订阅；`dispatch` 用 `inspect.isawaitable` 兼容 sync/async handler，单个 handler 异常被捕获记录、不影响事件循环与其他订阅；host 拒绝订阅时本地移除。`bridge.py` 新增 `ide.event.emit` 分发 arm 路由到 `events.dispatch`，DISPOSE 时自动 `events.dispose_all()`。`BasePlugin.__init__` 注入 `self.events`（三个子类共享）。  
协议变更：Envelope v1 结构不变；新增 `sdk.events.subscribe`、`sdk.events.unsubscribe`（插件→IDE，带 subscriptionId/topic/filter/delivery）和 `ide.event.emit`（IDE→插件，带 subscriptionId/topic/events 列表）三个消息类型，携带在 `payload` 而非 `data`。新增共享夹具 `test/fixtures/protocol/protocol_v1_events.json`，两仓库内容一致。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk test/core/sdk lib/pages/plugins`；`flutter test test/core/sdk test/pages/plugins test/features`；SDK `python -m unittest tests.test_events_api tests.test_events_fixtures tests.test_protocol_fixtures`、`python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 134 tests 通过（新增事件总线核心 13 项、协议往返 3 项、协议夹具 3 项）；SDK T12 定向 12 tests（events_api 10、events_fixtures 2）全部通过，compile 通过；SDK 全量 150 tests 仍为 T00 已记录的 4 failures、5 errors，无 T12 新增回归；两仓库 diff 仅 LF/CRLF 提示。  
偏差/后续事项：editor.*/runtime.* topic 已在注册表声明但 payload 生产分别归属 T13/T14；`every` 模式的真实队列溢出需在传输 sink 阻塞时才出现，核心单测仅验证限额接线，端到端背压归属 T21。T13 未开始。

任务：T13  
提交：工作区未提交  
IDE 修改：新增 `document_registry.dart`（`DocumentRegistry` + `RegisteredDocument`）为每个打开文档铸造稳定 documentId（按宿主 handle 而非路径键控，关闭再打开得到新 id），跟踪 active 文档；新增 `document_service.dart`（`PluginDocumentService`，无 Flutter 依赖）按快照 diff 发出 opened/closed/saved/activeDocument.changed，`notifyContentChanged` 发送增量 changes（dirtyRegion，不带完整正文）、`notifySelectionChanged` 发送选区；新增 `api/document_api.dart`（`SdkEditorDocument`）绑定 5 个命令 active_document.get/document.get/document.symbols/document.reveal/document.selection.get，symbols 结果带 requestRevision 与 stale 标记，LSP 不可用时返回 `unavailable` 错误码；新增 `editor_document_host.dart`（`EditorDocumentHost` + `_ControllerAccess`）通过 `ref.listen(tabbedViewControllerProvider)` 桥接真实标签模型，按 `contentVersion` 单调版本 + `selectionOnly` 标志区分内容/选区变更，复用 code_forge `getDocumentSymbols`（LSP `textDocument/documentSymbol`），reveal 用 documentId/line/column 定位而不暴露 controller，过滤 `type=='file'`；`permissions.dart` 登记 5 个命令（4 读 1 写）；run manager provider 在 `_bindManager` 非 dataOnly 时 bind 文档 API 并初始化宿主监听。  
SDK 修改：新增 `api/document.py`（`Document`/`Position`/`Selection`/`DocumentSymbol`/`SymbolResult` typed model + `EditorDocuments`）提供 get_active/get/symbols/get_selection/reveal 查询封装（回调解析为 typed model，unavailable 走 error 回调）和 on_opened/changed/saved/closed/selection_changed/active_changed 订阅封装；DocumentSymbol 同时兼容层级 DocumentSymbol 与扁平 SymbolInformation；`UiPlugin`/`ServicePlugin` 注入 `self.documents`。  
协议变更：Envelope v1 结构不变；新增 `sdk.editor.active_document.get`/`document.get`/`document.symbols`/`document.reveal`/`document.selection.get` 请求命令，事件复用 T12 的 `ide.event.emit` 与 `editor.document.*`/`editor.activeDocument.changed` topic（T12 已注册）。新增共享夹具 `protocol_v1_editor_document.json`，两仓库字节一致。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk test/core/sdk`；`flutter test test/core/sdk test/pages/plugins`；SDK `python -m unittest tests.test_document_api tests.test_document_fixtures`、`python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 156 tests 通过（新增 registry 7、service 7、document API 5、协议夹具 4 = 22 项 T13 相关）；SDK T13 定向 16 tests（document_api 12、document_fixtures 4）全部通过，compile 通过；SDK 全量 166 tests 仍为 T00 已记录的 4 failures、5 errors，无 T13 新增回归；两仓库 diff 仅 LF/CRLF 提示。  
偏差/后续事项：`documentHostProvider` 默认读真实 `editorDocumentHostProvider`，测试用 `overrideWithValue` 注入 fake 避免拉入 code_forge；行/列基准沿用 code_forge 既有 `go_to_line` 语义（0 基 line）；AST fallback（LSP 不可用时）按任务说明留待后续；符号取消是通过 revision/stale 标记由插件侧丢弃旧结果，主动取消在途 LSP 请求归属 T18 大纲样板消费场景。T14 未开始。

任务：T14  
提交：工作区未提交  
IDE 修改：新增 `runtime_inspection.dart`（无 Flutter 依赖）：`RuntimeReference` 令牌 `runtime-<session>:generation-<gen>:obj-<id>` 绑定会话/代，`RuntimeInspectionService` 管理 RuntimeSession、按代铸造/校验引用（backend restart 时 `restartBackend` 递增 generation 使所有旧引用 stale）、驱动程序状态机（running/paused/resumed/finished）并发出 runtime.* 生命周期事件、`RuntimeLimits` 对 repr/子项分页设上限；新增 `api/runtime_api.dart`（`SdkRuntime`）绑定 6 个命令 sessions/state/scopes/variables/children/object_info（均 runtime:inspect），能力不可用或后端返回 null 时回 `unavailable` 错误码而不打断程序，children/object_info 先校验引用（stale→`stale_reference`、格式错→`invalid_request`），分页 start/count；新增 `device_runtime_host.dart`（`DeviceRuntimeHost` + `UnavailableRuntimeBackend`）通过 `ref.listen(serialProvider)` 从连接/断开/换口派生 runtime 会话生命周期（当前后端无协作式设备调试协议，一律 capability unavailable，满足"检查绝不发 CTRL-C"），断开/重连按代递增；`permissions.dart` 登记 6 个命令（均 runtime:inspect）；run manager provider 非 dataOnly 时 bind 运行时 API 并初始化设备宿主监听。  
SDK 修改：新增 `api/runtime.py`（typed `RuntimeSession`/`Scope`/`Variable`/`ObjectInfo`/`Page` + `Runtime`）提供 sessions/state/scopes/variables/children(懒加载、分页)/object_info 查询封装和 on_session_created/session_state_changed/program_started/paused/resumed/finished/backend_restarted/variables_changed 订阅封装；`stale_reference`→`StaleReferenceError`、`unavailable`→`RuntimeUnavailableError` 专用异常；`UiPlugin`/`ServicePlugin` 注入 `self.runtime`。  
协议变更：Envelope v1 结构不变；新增 `sdk.runtime.sessions/state/scopes/variables/children/object_info` 请求命令，事件复用 T12 `ide.event.emit` 与 `runtime.*` topic（T12 已注册，均 runtime:inspect）。新增共享夹具 `protocol_v1_runtime.json`，两仓库字节一致。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk test/core/sdk`；`flutter test test/core/sdk test/pages/plugins`；SDK `python -m unittest tests.test_runtime_api tests.test_runtime_fixtures`、`python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 178 tests 通过（新增 inspection 核心 12、runtime API 6、协议夹具 4 = 22 项 T14 相关）；SDK T14 定向 14 tests（runtime_api 11、runtime_fixtures 3）全部通过，compile 通过；SDK 全量 180 tests 仍为 T00 已记录的 4 failures、5 errors，无 T14 新增回归；两仓库 diff 仅 LF/CRLF 提示。  
偏差/后续事项（T14）：设备端真实变量读取需要协作式 MicroPython 检查协议（sys.stdin 非阻塞轮询 + 标记帧应答或 id() 句柄表），设备 REPL 现无此能力且每条执行路径都会先发 12×CTRL-C，故 T14 交付完整插件契约（API + 会话/代生命周期 + 引用失效 + capability unavailable 行为）与可插拔 `RuntimeBackend`，真实后端实现（含 `runtime.variables.changed` 的实际触发、program.started/finished 与 runCurrentFile 的接线）为独立后续，不改 API/SDK 契约即可替换 `UnavailableRuntimeBackend`；共享调度器（run 任务与检查统一）同属该后续。T15 未开始。

任务：T15  
提交：工作区未提交  
IDE 修改：新增 `view_model_store.dart`（无 Flutter 依赖）：`ViewInstanceId` 用 pluginId/sessionId/viewId/instanceId 四元组唯一标识实例（同一 viewId 可开多个实例互不串用，sessionId 保证重启会话无法 patch 旧实例）；`ViewModel` 持有有序节点模型与单调 revision，`applyPatch` 在工作副本上执行 insert/update/remove/move 全集，任一 op 失败即整体回滚（不产生部分状态），`baseRevision` 与当前 revision 不符返回 `revisionGap`，关闭后拒绝 patch，节点清空时状态转 `empty`；`ViewState` 区分 loading/ready/empty/error/disconnected；`ViewModelStore` 管理全部实例并提供 clearSession/clearPlugin/clear。新增 `view_model_store_provider.dart` 宿主级单例。新增 `api/view_api.dart`（`SdkView`）绑定 `sdk.view.open/snapshot/patch/close`，patch 成功回 `ide.view.ack`（带新 revision），失败回 `ide.view.nack`，其中 revisionGap/noSnapshot 追加 `ide.view.resync`（带宿主当前 revision）让插件重新收敛，invalidOperation 视为客户端 bug 不请求 resync。`plugin_run_manager.dart` 新增 `ide.view.ack/nack/resync` 与 `sdk.view.*` 常量及 `sendViewFrame`（握手完成前不投递）；`permissions.dart` 将 4 个 view 命令登记为 public（插件管理自有视图模型）；run manager provider 在 stop/移除/重启/退出四处清理视图实例。  
SDK 修改：新增 `api/view.py`：`ViewModel` 本地镜像模型 + revision 跟踪，`batch()` context manager 将多个操作合并为一个 patch 事务，最多一个 in-flight patch（等待 ack 期间新操作入队并在 ack 后合并发出），`ack`/`nack` 控制帧处理，nack 或错误响应触发 `resync()` 重发快照，`close()` 后拒绝新操作；`Views` 管理多实例并按 instanceId 路由 `ide.view.*` 帧，`resync_all()` 供重连后重发全部快照。`bridge.py` 新增 `ide.view.ack|nack|resync` 分发 arm；`UiPlugin` 注入 `self.views`。  
协议变更：Envelope v1 结构不变；新增插件→IDE 的 `sdk.view.open/snapshot/patch/close` 与 IDE→插件的 `ide.view.ack/nack/resync`，与 RFW 无关。新增共享夹具 `protocol_v1_view.json`，两仓库字节一致。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk test/core/sdk`；`flutter test test/core/sdk test/pages/plugins`；SDK `python -m unittest tests.test_view_api tests.test_view_fixtures`、`python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 197 tests 通过（新增 store 核心 12、协议接线 4、协议夹具 4 = 20 项 T15 相关）；SDK T15 定向 17 tests（view_api 13、view_fixtures 4）全部通过，compile 通过；SDK 全量 197 tests 仍为 T00 已记录的 4 failures、5 errors，无 T15 新增回归；两仓库 diff 仅 LF/CRLF 提示。夹具测试双向交叉校验：SDK 侧断言 `batch()` 产出的 ops 与夹具逐字节一致，IDE 侧断言同一夹具 patch 应用到真实 store 后节点顺序为 `[n3, n1]`，即两端对同一份契约收敛。  
偏差/后续事项（T15）：测试期发现注入帧的 sequence 必须严格递增，否则被 run manager 当重复帧丢弃（`_request` 辅助函数用自增序号）；`ViewModelStore` 目前是扁平有序列表模型，树形 renderer 的层级结构按 T16 `native.tree` 的 builder 需要再决定是否扩展 parentId/children 字段；视图状态 `error` 目前只由宿主侧设置，插件主动上报错误态的入口留待 T16 渲染层一并设计。T16 未开始。

任务：T16  
提交：工作区未提交  
IDE 修改：新增 `component_schema.dart`（无 Flutter 依赖）：`componentSchemaVersion = 1`，`PropSpec`（类型 + required + 闭集校验）、`ComponentSpec`（props/events/`ChildPolicy`/`allowedChildren`）、`ComponentLimits`（maxDepth 32、maxNodes 5000）、`ComponentRegistry` 声明第一批 32 个通用组件（布局 10 / 内容 6 / 输入 6 / 操作 7 / 数据 4，含规格要求的 SplitView、PropertyGrid 等），`validate()` 收集全部问题并以 `root.children[0].props.label` 形式给出路径，覆盖未知组件、未知/类型错误/缺失必需属性、非法值、未知事件、叶子节点带子节点、受限父节点的非法子类型、深度与节点数超限。新增 `renderer_registry.dart`：8 个 renderer token（`RendererTokens`）+ `RendererSpec`（rootComponent + requiredNodeFields），`validateAgainst` 保证每个 renderer 的根组件确实存在，`validateNodes` 校验模型节点字段。新增 `features/plugin_view/`：`component_error_boundary.dart` 把 schema 问题渲染成可诊断面板而非崩溃页面；`component_host_state.dart` 输入控件的 controller/focus/本地缓冲全部宿主本地，change 事件按 200ms 去抖，聚焦或存在未确认编辑时拒绝被插件的旧值覆盖；`component_builder.dart` 32 个组件的 widget 映射（图标走稳定 token 表，不暴露 `IconData`；schema prop 名不映射 Flutter 构造参数）；`native_view_registry.dart` 把 8 个 renderer token 映射到 Flutter builder，renderer 本身用组件树表达以继承主题/事件/错误处理，`native.form` 按节点 kind 映射输入组件。`plugin_run_manager.dart` 新增 `ide.view.event` 常量；`api/view_api.dart` 新增 `sendComponentEvent` 投递组件事件。  
SDK 修改：新增 `api/components.py`：`Component`（dict 子类，`to_json()` 把 handler 降为 `{event: True}` 标记）+ 32 个构建器函数（snake_case 参数 → camelCase prop，None 值自动省略），`collect_handlers` 递归收集 `(component_id, event) -> handler`；`api/view.py` 的 `ViewModel` 在每次 snapshot/patch 后重建 handler 表（移除的组件其 handler 一并失效），新增 `dispatch_event`，`_wire_nodes()` 输出可序列化 wire 形式；`Views.handle_frame` 增加 `ide.view.event` 路由；`bridge.py` 分发 arm 加入 `ide.view.event`；`UiPlugin` 注入 `self.views`（T15 已有）。  
依赖变更：新增 `material_table_view: ^5.5.2`（`TableView.builder` 按行懒构建 + `TableColumn` 冻结/粘性/弹性列，供 T17 的 DataTable 使用）；`TreeView` 复用仓库内已有的 `super_tree` path 依赖（`SuperTreeView<T>` + `TreeController`，已在文件浏览器 8 处实战使用）。两者的能力已反映到 schema props（DataTable 的 rowCount/rowHeight/showHeader、TreeView 的 indent/searchable/contextMenu、VirtualList 的 itemCount），但不暴露包的构造参数。  
协议变更：Envelope v1 结构不变；新增 IDE→插件的 `ide.view.event`（instance + componentId + event + payload）。组件树作为 view 模型节点数据传输，复用 T15 的 `sdk.view.snapshot/patch`。新增共享夹具 `protocol_v1_components.json`，两仓库字节一致。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk lib/features/plugin_view test/core/sdk test/features`；`flutter test test/core/sdk test/features test/pages/plugins`；SDK `python -m unittest tests.test_components tests.test_component_fixtures`、`python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 238 tests 通过（新增 schema/renderer 16、widget 层 19、协议夹具 5 = 40 项 T16 相关）；SDK T16 定向 26 tests（components 21、component_fixtures 5）全部通过，compile 通过；SDK 全量 223 tests 仍为 T00 已记录的 4 failures、5 errors，无 T16 新增回归；两仓库 diff 仅 LF/CRLF 提示。夹具沿用 T15 的双向交叉校验：SDK 侧断言构建器产出的验收页面与夹具 `to_json()` 完全相等，IDE 侧断言同一页面通过校验且 8 个非法树各自在预期路径给出预期错误，事件夹具在两侧分别校验 envelope 与 handler 分发。验收标准三项均有对应测试：Toolbar + SearchField + VirtualList 组成完整页面并保持可交互、未知组件/属性显示可诊断错误边界且 `takeException()` 为 null、主题在明暗模式下解析出不同的 `onSurfaceVariant`。  
偏差/后续事项：修复了 widget 测试暴露的两处生产缺陷——(1) `InkWell` 同时设置 `onTap`/`onDoubleTap` 会让选中延迟一个双击超时，改为手动检测双击（`_tapRow`），选中立即响应、快速二次点击再补发 `activate`；(2) 插件把滚动组件嵌进无界高度容器（合理写法）会触发 Flutter 断言，`Flex` 与四个数据组件改为 `LayoutBuilder` 探测约束，无界时 shrink-wrap，因为"非法布局不能崩溃页面"与"未知组件不能崩溃页面"是同一条要求。另修复 SDK 一处序列化缺陷：`snapshot()` 原先用 `dict(n)` 复制会把 `Component` 降级为普通 dict，导致 handler 函数对象直接进入 wire 层无法 JSON 序列化，改为保留 `Component` 实例。数据组件（VirtualList/TreeView/DataTable/PropertyGrid）当前为 `ListView.builder` 基础实现，高性能版本（super_tree、material_table_view、增量可见索引、键盘导航、分页）归 T17；SplitView 可拖拽分隔条、Markdown 真实渲染同属后续；插件主动上报视图 `error` 状态的入口仍未开放。T17 未开始。

任务：T17  
提交：工作区未提交  
前置测量（决定架构的依据）：先对 `super_tree` 的 `TreeController` 实测，而非按静态阅读下结论。初读时因 `_rebuildFlatList()` 有 17 个调用点，误判为"每次更新都整树 flatten、与规格冲突"；实测推翻该判断——`expandNode` 走 `_flatVisibleNodes.insertAll(index + 1, descendants)` 增量拼接，仅在节点不在扁平表时回退整树。Windows debug 实测：构建 10k 节点 controller 40ms、100k 约 900ms；100k 树中展开单节点约 2ms、折叠约 5ms、反复展开折叠均摊 **8µs/次**；但 `addRoot` 到 100k 树需 **37ms**（走整树 flatten），且控制器**无 batch 或抑制通知 API**，故一个 T15 patch 事务含 N 个结构 op 就是 N 次整树 flatten。化解点在于 37ms 是完全物化 100k 节点时测得，而规格要求的是"100,000 **逻辑**节点在**懒加载**下"——懒加载意味着永不同时物化 100k 节点。据此定分层方案：复用 super_tree 的渲染与展开能力，另建规格指定的增量索引承接 T15 patch，每个事务同步一次而非每 op 一次。  
IDE 修改：新增 `tree_index.dart`（无 Flutter 依赖），实现规格点名的四个结构 `nodeById`/`childrenByParent`/`expandedNodeIds`/`visibleNodeIds`，外加 `_visibleIndexById` 使行号查找 O(1)；`TreeNodeModel.label` 可变，故单节点改名不触碰任何索引；`expand`/`collapse` 只对受影响区间做 `insertAll`/`removeRange` 并局部重建行号，`reset` 是唯一的全量重建；`insert` 会锚定到前一兄弟的最后一个可见后代之后（避免插到子树中间），父节点折叠时只改结构不动可见表；`remove`/`move` 按子树跨度整段摘除；`ChildrenState`（loaded/unloaded/loading/error）+ `needsChildren`/`attachChildren` 支撑懒加载与错误重试。新增 `features/plugin_view/data/`：`visible_range_tracker.dart` 把滚动期的缺口请求按 chunk 去重 + 120ms 去抖，已请求过的 chunk 永不重复请求；`plugin_virtual_list.dart` 稀疏窗口（`itemCount` 可远超已加载 `items`，缺口渲染占位骨架）、固定 `itemExtent`、键盘导航（上下/Home/End/Enter，落入未加载区间时只请求不跳选）；`plugin_tree_view.dart` 由 `TreeIndex` 驱动的虚拟化树，含展开/折叠、懒加载 spinner、错误行重试、右键上下文菜单、方向键导航（右键展开或下移、左键折叠或跳父）、`refresh()` 供索引被外部改动后重绘；`plugin_data_table.dart` 基于 `material_table_view` 的 `TableView.builder`（懒建行 + `TableColumn` 的 width/flex/freezePriority），`rowBuilder` 对未加载行返回 null 以渲染占位并触发合并请求，表头点击发 sort 事件并显示升降序箭头。`component_host_state.dart` 新增按组件 id 缓存的 `TreeIndex` 与 `_reconcile`：节点 id 集合不变时只就地刷新 label/icon/childrenState（保住展开态与可见索引），集合变化才重建并把展开集合带过去。`component_builder.dart` 的 VirtualList/TreeView/DataTable 三个基础实现替换为上述组件，删除随之失效的 `_row`/`_tapRow`。  
SDK 修改：无（T17 为纯 IDE 渲染层任务，组件契约沿用 T16 的 schema，未改协议）。  
协议变更：无。schema 未变（T16 已为 `itemCount`/`rowCount`/`rowHeight`/`indent`/`childrenState` 等预留 props），无新增夹具。  
验证命令：`flutter analyze --no-fatal-infos lib/core/sdk lib/features/plugin_view test/core/sdk test/features`；`flutter test test/core/sdk test/features test/pages/plugins`；SDK `python -m compileall -q src`、`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。  
验证结果：IDE analyzer 零问题，回归 289 tests 通过（新增 tree_index 27、性能门槛 17、super_tree 基准 7 = 51 项 T17 相关）；T16 的 19 个 widget 测试在数据组件被整体替换后**全部原样通过**，说明组件契约未破。SDK 未改动，compile 通过，全量 223 tests 仍为 T00 已记录的 4 failures、5 errors。两仓库 diff 仅 LF/CRLF 提示。四条性能门槛均有实测断言：(1) 10k 快照可加载——VirtualList 首帧 497ms、TreeView 92ms，各只构建 <60 行；(2) 100k 逻辑节点不创建 100k widget——1000 根声明各 100 个未加载子节点，模型只物化 1000 个、widget <60；(3) 单节点 label 更新不重建整表——500 节点树重建 **28 行**（仅可见窗口），且 `visibleNodeIds` 逐项不变；(4) 滚动期无 Python RPC——全加载列表拖动两次共 **0 次**请求，滚入缺口仅 **1 次**合并请求，60 帧连续缺口合并为 1 次，重复滚过同一 chunk 不再请求。增量性对比：同为万级树，`TreeIndex` 展开+折叠 **22.6µs/次**、10k 次 relabel 共 1ms（**0.19µs/次**），而 super_tree 同规模 `addRoot` 为 37ms，差约三个数量级，印证分层取舍。  
偏差/后续事项：修复两处生产缺陷——(1) 点击行不会让外层 `Focus` 取得焦点，导致点选后方向键失效，两个列表组件的 `_select` 补 `requestFocus()`（点一行再用键盘继续导航是理所当然的期望）；(2) 测试期发现从外部调用 `State.setState` 属违规用法，改为在 `PluginTreeViewState` 暴露公开的 `refresh()`——索引是宿主拥有且可变的（这正是 relabel 只花一行代价的前提），故由改动索引者负责请求重绘。另记一处测试陷阱：`pumpAndSettle` 不推进挂起的 `Timer`，去抖类断言须显式 `pump(duration)`。`super_tree` 的 `SuperTreeView` widget 本身未直接用于插件树（其 `TreeNode.data` 为 final、结构操作无 batch API，与 patch 事务模型不契合），但其控制器的增量展开策略经实测确认可靠、文件浏览器 8 处仍在使用，将来若开放"插件复用文件树 UI"可直接接入；`material_table_view` 的列宽拖拽（`TableColumnControlHandlesPopupRoute`）、行重排（`TableRowReorder`）、`TablePlaceholderShade` 微光效果尚未启用；DataTable 尚无键盘导航（VirtualList/TreeView 已有）；`itemHeight` 可变行高（`rowHeightBuilder`）未开放。T18 未开始。

任务：T18-TA/TC (部分)  
提交：工作区 (TA 路由 + TC 标签页视图宿主 + TB 渲染面完成；TD 组件缺口未完成)  
IDE 修改：  
  - (TB 已完成) `lib/features/plugin_view/plugin_view_surface.dart` — 单一渲染面,订阅 `store.listenableFor(instance)`,渲染自由组件树或委托 `NativePluginViewRegistry`;`lib/pages/plugins/main.dart` 的 `PluginViewHost` 现返回 `PluginViewSurface` (instanceId `container:<containerId>`),替换原 RFW 返回值;`lib/core/sdk/view_model_store.dart` 增加通知能力 (`listenableFor(instance)`,installSnapshot/applyPatch(ok)/setState/close/clearSession/clearPlugin 均触发 `_notify`)。8 个渲染面测试 + 303 回归通过。
  - (TA 完成) `lib/core/sdk/view_route_stack.dart` — `ViewRouteStacks` 按完整 `ViewInstanceId.key` (含 instanceId) 分隔栈,操作 push/pop/replace/goto/current/stackOf;`lib/core/sdk/api/view_api.dart` 新增 4 个路由处理器 (`_handleRoute`,`_handleRoutePop`),发 `IdeCommands.viewRouteSync`;`lib/core/sdk/permissions.dart` 登记 4 条 `sdk.view.route.*` 为公开命令;`lib/core/sdk/plugin_run_manager.dart` 新增 4 个命令常量 (`SdkCommands.viewRoutePush/Pop/Replace/Goto`,`IdeCommands.viewRouteSync`)。测试覆盖实例隔离、根栈 pop 返回 false、goto 折叠栈。
  - (TC 完成) `lib/core/models/editor.dart` — `TabDataValue` 新增 `pluginId`/`viewId`/`viewInstanceId`/`renderer` 字段,type `plugin_view` 判别;`lib/core/services/editor/tabbed_view_controller_provider.dart` — `openPluginView({pluginId,viewId,renderer,title?,expansion?})` 分配 instanceId `tab:<counter>`,构造 `TabData` 内容为 `PluginViewSurface`,插入主编辑器或拓展页控制器;`afterTabClose` 路径在 type=`plugin_view` 时调 `viewModelStoreProvider.close(instance)`;`lib/core/sdk/api/tab.dart` — 新增 `sdk.tab.create_view` 处理器,从贡献点解析 renderer,回应创建的 instanceId;`lib/core/sdk/permissions.dart` 登记 `sdk.tab.create_view` 需 `tab:create` 权限。测试证实同一 viewId 在 sidebar 和 tab 中是两个独立 `ViewInstanceId`、独立模型、关闭 tab 不影响 sidebar 实例。
SDK 修改：  
  - (TA 完成) `src/pyrite_sdk/api/view.py` — `ViewModel` 新增 `push_route(route,params?,callback?)`/`pop_route()`/`replace_route(route,params?)`/`goto_route(route,params?)`,属性 `route`/`route_stack`/`route_params`,`on_route(handler)` 订阅,`route_sync(route,stack,params)` 内部更新并触发订阅;`Views.handle_frame` 路由 `ide.view.route.sync`;`src/pyrite_sdk/core/bridge.py` 在已有 `ide.view.*` 匹配臂加 `ide.view.route.sync`。测试覆盖 push 带 params、pop/replace/goto 命令类型、sync 更新栈与触发订阅、关闭视图后路由调用被拒。
  - (TC 未做 SDK 侧 API,无需改动 — 标签页宿主纯 IDE 侧能力)
协议变更：新增 4 条路由命令 (`sdk.view.route.push/pop/replace/goto`,IDE 回 `ide.view.route.sync` 含 route/stack/params);新增 `sdk.tab.create_view` (payload {viewId,renderer?,title?,expansion?},回应 {instanceId})。无新增共享夹具 (TA/TC 均为实例隔离/路由栈管理,逻辑不跨仓库)。  
验证命令：IDE `flutter analyze --no-fatal-infos lib test`、`flutter test`;SDK `python -m compileall -q src`、`python -m unittest discover -s tests`;两仓库 `dart format lib test`、`git diff --check`。  
验证结果：  
  - IDE analyzer **60 issues**(全部为已存在的 `use_build_context_synchronously` info 警告,与本次变更无关);集成期修复 1 处 `plugin_markdown.dart` 语法错误 (TD agent 写了但未完成验证即超时)。
  - IDE 测试 **420 pass,10 fail** (10 个失败全部为已存在的 `ui_utils_test`/`raw_paste_session_test`/`git_repository_service_test`,无新增失败)。
  - SDK **231 tests,4 failures + 5 errors** (与 T00 基线完全一致,均在 legacy UI/RFW 测试中)。
  - 格式化: `dart format` 改动 27 个文件;两仓库 `git diff --check` clean (忽略 CRLF/LF)。
  - 独立实例验证通过: sidebar instanceId `container:<containerId>`、tab instanceId `tab:<counter>`,`ViewRouteStacks._stacks` 按完整 `instance.key` 索引,同一 viewId 在两处同时打开互不影响对方的模型和路由栈。
偏差/后续事项：  
  - **TD 组件缺口审计未完成** (Cloudflare 524 超时,agent 工作 120 秒后被代理层断开)。原计划审计 32 个组件的完整性并补齐 Markdown 真实渲染 (使用 `markdown_widget` 而非 `SelectableText`)、SplitView 可拖拽分隔、Dialog 宿主模态层路由、DataTable 键盘导航。**本条延后处理**: 当前 TB/TA/TC 已集成干净,可先推进 T18 (大纲视图验收) 或 TE (环境 API);TD 稍后单独重试,具体补齐项见原 workflow 脚本 `C:\Users\can1425\.claude\projects\E--Can1425-pyrite-ide\9e587b27-599b-4d4f-8fc0-9639329a5139\workflows\scripts\plugin-view-gaps-wf_86d1f84b-2e1.js` 的 TD 指令段 (line ~205-260)。TD 延后不阻塞后续任务,因为已有的 32 个组件 schema + 16 个 builder (T16) + 3 个虚拟化数据组件 (T17) 足够搭建验收插件。
  - TC 的 `expansion` 参数已实现 (两个控制器路径都通),但缺少端到端测试证实"拓展页标签页真能工作"——可在 T18 大纲视图验收时一并确认。
  - TA 完成时,旧的插件级路由栈 (`PluginRunManager.currentRoute`/`routeStack`/`_handleRouterPush` 等,约 `plugin_run_manager.dart:272` 附近) 仍在原地未删除,因为 TA agent 被指令"不动 plugin_run_manager.dart 除了新增常量外的任何内容"以避免与 TC 撞车。这些遗留字段与处理器现已无用 (新协议用 per-instance 栈),应在清理遗留代码时统一删除 (或在确认无引用后立即删)。
  - TB 在集成验证后 `plugin_markdown.dart:43` 仍报语法错误被修复 (TD agent 写入但验证未完成),修复为删除尾随逗号。该文件为 TD 任务的一部分,需在 TD 重试时整体验收。

任务：TE（环境 API — 平台 + 布局模式）
提交：工作区未提交
IDE 修改：新增 `EnvironmentSnapshot`/`LayoutMode`/`EnvironmentNotifier`，缓存 os、isDesktopPlatform、layoutMode、width/height、locale、themeMode，并只在语义字段（布局模式、locale、主题）真正变化时去抖通知；新增 `SdkEnv`（`sdk.env.get`）与 `EnvironmentBroadcaster`，后者挂在 `ResponsiveBreakpoints` 作用域内部，把 `ResponsiveBreakpoints.of(context)` 的 isMobile/isTablet/isDesktop 映射为统一的 layoutMode，并通过 `ide.env.changed` 推送给所有运行中的插件会话。`sdk.env.get` 列入 publicCommands（不含用户数据，移动端布局必需）。
SDK 修改：新增 `api/environment.py`，提供 `env.get()` 与 `env.on_change()`；`bridge.py` 路由 `ide.env.changed` 到该 API，沿用既有 `inspect.isawaitable` 约定同时支持 sync/async handler。
协议变更：Envelope v1 结构不变。新增 `sdk.env.get`（请求/响应）与 `ide.env.changed`（宿主推送）两个消息类型。
验证命令：`flutter test test/core/sdk/environment_test.dart`；`flutter test test/core/sdk test/features test/pages/plugins`；`flutter analyze --no-fatal-infos lib test`；`python -m unittest discover -s tests`；`dart format`；两仓库 `git diff --check`。
验证结果：TE 定向 6 tests 通过（覆盖快照序列化、布局上报前可读、去抖通知、同模式内 resize 不唤醒插件、跨断点连续变化合并为一次通知、主题/locale 变化通知）；插件回归 338 tests 全部通过；analyzer 无 error/warning（60 条既有 info）；SDK 全量 231 tests 仍为既有 4 failures、5 errors（全部来自 T00 已记录的 RFW/`ai_plugin` 基线），无新增回归；格式化与 diff 检查通过。
偏差/后续事项：断点阈值沿用既有 `ResponsiveBreakpoints` 配置，未引入插件专属阈值，避免宿主与插件布局判断分叉。TD（Markdown/SplitView/Dialog/DataTable 补全）仍未开始。

任务：T18（当前进展，尚待真实插件打包/安装/运行验收）  
提交：工作区未提交  
IDE 修改：`PluginViewSurface` 在视图实例挂载、切换和卸载时通过新增的 `ide.view.visibility.changed` 推送可见性；`SdkView.sendVisibilityChanged` 使用完整 `ViewInstanceId` 定位实例，插件可在视图隐藏时暂停非关键刷新。为 renderer 根事件补齐既有 `ide.view.event` 的端到端验证，原生 outline 行点击由宿主按 viewId 发回插件。  
SDK 修改：新增真实 Manifest v2 示例插件 `examples/debug_enhanced_plugin`，插件名“调试加强”，T18 阶段声明 `debug-enhanced` 导航容器和 `debug-enhanced.outline`/`native.outline` 视图；`OutlineController` 订阅 activeDocument.changed/document.changed/document.saved，内容变化使用宿主 100ms debounce，按 document/request epoch 丢弃迟到结果，LSP symbol 以父路径、kind、名称和源码位置生成稳定 ID，使用 snapshot 初始化后只发事务 patch，行点击调用 document.reveal。空文档、解析中、LSP unavailable 和普通错误均有明确状态；视图隐藏时取消当前 epoch 并延后刷新。`ViewModel.on_event` 为 renderer 根注册显式 handler，`on_visibility` 接收实例可见性变化，二者均按实例隔离。  
协议变更：Envelope v1 不变；新增 IDE→SDK 的 `ide.view.visibility.changed`，payload 为 `{instance, visible}`。两仓库 `protocol_v1_view.json` 同步新增夹具，SHA-256 均为 `49B86DCB8956A8E09BECBF8A8F2EC534BDEBB333444C57B8EB1523052C154926`。  
验证命令：IDE `dart format`（T18 文件）、`flutter analyze --no-fatal-infos lib test`、`flutter test test/core/sdk test/features test/pages/plugins`、`git diff --check`；SDK `python -m compileall -q src examples/debug_enhanced_plugin`、`python -m unittest tests.test_view_api tests.test_view_fixtures tests.test_debug_enhanced_outline`、`python -m unittest discover -s tests`、`git diff --check`。  
验证结果：IDE 定向 view/协议/surface 24 tests 通过，插件回归 339 tests 全部通过；analyzer 仅 60 条既有 info，无 error/warning。SDK T18 定向 35 tests 通过，全量 241 tests 仍为 T00 已记录的 4 failures、5 errors，无新增失败；新增示例通过 Manifest v2/权限打包器校验。两仓库 diff 检查通过（仅既有 LF/CRLF 提示）。验收测试覆盖稳定树映射、增量 patch、快速文件切换迟到结果、reveal、空/unavailable/error 状态与视图可见性暂停。  
偏差/后续事项：当前自动化验证通过，但尚未将 `examples/debug_enhanced_plugin` 打包、安装到 IDE 并在真实编辑器/LSP 会话中验证启动、符号刷新和点击 reveal，因此 T18 保持 `[~]`。T18 仅加入 Outline；同一“调试加强”插件的 Variables 贡献、runtime reference/cache 和分页懒加载严格留给 T19。请求的传输级 cancellation/deadline 属 T21，本任务使用单调 request epoch 实现可观察行为上的取消，保证迟到 LSP 结果无法覆盖当前文档。插件国际化与 TD 组件补全不属于 T18，未在本任务扩展。

任务：T18（树形、无 LSP 回退和标签页实例补充，仍待安装验收）  
提交：工作区未提交  
IDE 修改：本次未新增宿主实现；复用已完成的 `sdk.tab.create_view` 主编辑区/拓展区放置和每标签页独立 `instanceId`。  
SDK 修改：`examples/debug_enhanced_plugin` 升级为 1.1.0。Outline 保留层级 `DocumentSymbol.children`，并对扁平 `SymbolInformation` 按完整 range 最近包含关系、`containerName` 回退重建父子树；LSP unavailable 或空结果时通过 `document.get` 读取当前未保存缓冲区，采用 Thonny 风格逐行正则和缩进栈识别 class/def/async def，不依赖完整 AST，1 MiB 或 20,000 行以上明确拒绝。新增根级“在主编辑区打开大纲”和“在拓展区打开大纲”操作项；新增 `api/tab.py` 的 `Tabs.create_view`/`TabViewInstance` 并注入 `UiPlugin.tabs`，插件为宿主返回的每个实例创建独立 `ViewModel`，同步相同 Outline 快照和后续 patch。Manifest 新增 `tab.create`，并补上 document.reveal 所需的 `editor.write`。  
协议变更：无；使用既有 `sdk.editor.document.get`、`sdk.tab.create_view` 和 `sdk.view.*`。  
验证命令：SDK `python -m unittest tests.test_tab_api tests.test_debug_enhanced_outline tests.test_packager_runtime`、相关 85-test 组合、全量 unittest、`python -m compileall`、`git diff --check`；IDE `flutter test test/core/sdk/tab_view_host_test.dart`；从当前工作树构建 wheel 后用本地 wheel 打包 Windows 插件并检查 ZIP。  
验证结果：新增/相关 49 项及扩展相关 85 项全部通过；IDE tab 宿主 7 项全部通过；SDK 全量仍为既有 4 failures、5 errors，无新增回归。Windows ZIP 含新版插件源码和 `site-packages/pyrite_sdk/api/tab.py`，无 `__pycache__`/`.pyc`，以目标 CPython 3.14 解包导入烟雾测试通过。产物 `E:\Can1425\pyrite-sdk\build\debug-enhanced-Windows.zip`，5,870,890 bytes，SHA-256 `C8702DD651925E5A74C9896A52298A51317B1DF7507DA2DD02A2FCA468116E2F`。  
偏差/后续事项：仍需用户在真实 IDE 安装 1.1.0 包，验证树形展开、LSP 开/关两条路径和主/拓展标签页显示；完成该人工验收前 T18 保持 `[~]`。

任务：T18（Mobile document.reveal 历史问题修复，仍待设备验收）  
提交：工作区未提交  
IDE 修改：`DocumentHost.reveal` 改为宿主级异步操作。`EditorDocumentHost` 先选中目标文件标签；若 `CodeForgeController.scrollToLine` 因 Mobile/Tablet 独立页面尚未挂载编辑器而抛出 `Editor is not initialized`，此时才导航到 `/editor`，等待编辑器 render object 初始化后重试定位和光标设置。桌面端已挂载时仍走单次同步成功路径，不改变当前插件视图路由。等待超时或宿主异常由 `SdkEditorDocument` 转成 `unavailable` 响应，不再泄漏为 Flutter 未捕获异常。  
SDK 修改：无。  
协议变更：无；`sdk.editor.document.reveal` 成功响应结构不变，编辑器无法在约 2 秒内初始化时使用既有 error response 返回 `unavailable`。  
验证命令：`flutter test test/core/sdk/document_api_test.dart test/core/sdk/editor_document_host_test.dart`；`flutter analyze --no-fatal-infos`（document host/API/service 与两项测试）；`flutter test test/core/sdk`；`dart format`；`git diff --check`。  
验证结果：定向 8 项通过，scoped analyzer 无问题，完整 core/sdk 274 项全部通过。新增覆盖首次未挂载后重试成功、永久未挂载时有界超时，以及宿主 reveal 异常转换为协议错误。  
偏差/后续事项：自动化无法替代真实 Mobile 路由挂载时序，需用户用插件 Outline 点击符号确认页面切换、滚动与光标定位；验证前 T18 仍保持 `[~]`。

任务：T18/T19（Outline 交互完善并开始设备变量真实插件，均待设备验收）  
提交：工作区未提交  
IDE 修改：`native.outline` 和 `native.variableInspector` 增加宿主原生紧凑 AppBar，模型中 `role=appBarAction` 的节点成为带 tooltip 的图标操作，不再占用数据行；Outline 的主编辑区/拓展区入口均移至 AppBar。`role=placeholder` 作为居中状态展示，无标签页或非文本标签页时明确提示打开/切换到文本文件。TreeView 增加完整 LSP SymbolKind 图标 token 和宿主语义色解析，增量 reconcile 同步 `data`/`hasChildren`，避免图标颜色滞留。`PropertyGrid` 改为树形变量检查器，同行显示 name/type/repr，支持容器展开、`requestChildren`、键盘和虚拟滚动。  
SDK 修改：真实示例插件 `examples/debug_enhanced_plugin` 升级到 1.2.0，Manifest 新增“设备变量”/`native.variableInspector` 视图和 `runtime.inspect` 权限。Outline 为 LSP 1-26 全部 SymbolKind 映射不同图标与语义色。新增 `DeviceVariablesController`：监听 session state、paused、finished、backend.restarted、variables.changed；按 globals/locals/nonlocals 作用域加载顶层变量；按 reference 懒加载 children；每页 100 项并提供继续加载节点；repr 限制 2000 字符；后端重启立即清空 reference/page cache 并用 epoch 丢弃迟到响应；运行中或 capability unavailable 时明确展示不可用且不执行设备代码。修复 `Views` 原先仅以 instanceId 路由导致同容器多视图互相覆盖的问题，改为 `(viewId, instanceId)` 复合键，唯一旧实例查询仍兼容。  
协议变更：无；复用既有 `sdk.runtime.*`、`runtime.*` 事件、`sdk.view.*` 和 `ide.view.event`。  
验证命令：IDE `flutter analyze --no-fatal-infos`（本次渲染文件与测试）、`flutter test test/features/plugin_view/component_builder_test.dart`、`flutter test test/features/plugin_view`、`flutter test test/core/sdk`；SDK `python -m unittest tests.test_view_api tests.test_debug_enhanced_outline tests.test_debug_enhanced_device_variables tests.test_packager_runtime`、`python -m unittest discover -s tests`、`python -m py_compile`；构建当前 SDK wheel 后打包 Windows 插件，检查 ZIP 清单/缓存文件并用目标 CPython 3.14.6 解包导入。  
验证结果：IDE scoped analyzer 无问题，组件定向 21 项、plugin_view 全量 62 项、core/sdk 全量 274 项通过。SDK 相关 79 项通过，全量 263 项仍为 T00 已记录的 4 failures + 5 errors，无新增回归。Windows 包 `E:\Can1425\pyrite-sdk\build\debug-enhanced-Windows.zip` 为 5,876,400 bytes，SHA-256 `C9AE7DDF99AB4E15D59459D4EA2EED9BFE138C4BF6D82AF7990A0A4B92D43AAA`；1368 个条目，无 `__pycache__`/`.pyc`/`.pyo`，CPython 3.14.6 导入和复合视图路由 smoke test 通过。  
偏差/后续事项：T18 仍需用户在真实 IDE 验证 AppBar、占位、符号色彩图标和主/拓展标签页。T19 保持 `[~]`：当前 `DeviceRuntimeHost` 使用 `UnavailableRuntimeBackend`，因为现有设备 REPL 的每条执行路径进入前都会发送 CTRL-C，不能安全冒充变量读取；本轮交付真实可安装的设备变量插件、完整事件/cache/paging/UI 链路及明确 unavailable 状态。要显示真实设备值，仍需协作式 MicroPython 检查协议或新的无中断宿主 backend，并在真实设备上验证。

任务：TD（插件 View 上层封装与组件缺口收口）  
提交：工作区未提交  
IDE 修改：`Markdown` 通用组件和 `native.markdown` 统一接入既有 `PluginMarkdown`/`markdown_widget`，支持宿主主题、可选文本、代码块和 `linkTap` 事件；新增宿主级 `PluginSplitView`，支持任意面板数量、水平/垂直拖动和本地比例状态；新增 `PluginDialogHost`，使用 `DialogRoute` 在根 Navigator 展示真实模态层，插件关闭与用户 dismiss 分离；`PluginDataTable` 新增本地焦点、上下/Home/End/Enter 键盘导航和即时选择状态。`NativePluginViewRegistry` 识别 `role=viewConfig` 保留节点，将 renderer facade 的动态配置合并为组件 props 且不渲染为数据行。  
SDK 修改：`NativeViewNode`、`OutlineItem`、`VariableEntry`、菜单项和数据项补齐固定字段属性；renderer 的 select/activate/requestChildren 回调直接传回原始 typed item。新增 `TreeItem`、`VirtualListItem`、`TableRowItem`、`TableColumn`、`FormField`、`MarkdownContent`、`LogEntry`，以及 `views.tree/virtual_list/table/form/markdown/log` 六个 typed facade；组件层新增 typed `TableColumn`、`PropertyEntry`、`SelectOption`、`RangeRequest`、`MarkdownLinkEvent`，列表/树/表格/PropertyGrid 回调返回业务对象。`debug_enhanced_plugin` 的 Outline 和设备变量回调全部从 `payload.get("nodeId")` 迁移为 `node.id`。  
协议变更：Envelope v1 和命令集合不变。组件 schema 的 `Markdown` 新增可选 `id` 和 `linkTap` 事件；renderer 模型允许 SDK 写入保留的 `role=viewConfig` 节点传递 columns、itemCount 等宿主组件 props。  
验证命令：IDE `flutter analyze --no-fatal-infos lib/core/sdk/component_schema.dart lib/features/plugin_view test/features/plugin_view`、`flutter test --concurrency=1 test/core/sdk/component_schema_test.dart test/core/sdk/protocol_v1_components_test.dart test/features/plugin_view/component_builder_test.dart test/features/plugin_view/data_performance_test.dart`、`flutter test --concurrency=1 test/features/plugin_view`、`dart format`、`git diff --check`；SDK 89 项 components/native views/example/view 定向 unittest、全量 unittest、wheel 构建、Windows 插件打包和 ZIP 清单检查。  
验证结果：IDE analyzer 无问题；schema/协议/组件/性能组合 64 项通过，plugin_view 全量 67 项通过。SDK 定向 89 项通过；全量 277 项仍为既有 RFW/UI 基线的 4 failures + 5 errors，无本轮新增失败。真实示例插件升至 1.5.0；Windows 包 `E:\Can1425\pyrite-sdk\build\debug-enhanced-Windows.zip`，5,906,735 bytes，SHA-256 `2E45DC54F33F4571030018BD6D95B3C814AA37AFFB44CED56ACA594A38280B00`，1398 个条目，无 `__pycache__`/`.pyc`/`.pyo`。  
偏差/后续事项：本轮不删除 RFW、不扩展 renderer 目录、不增加新的宿主命令；Markdown 外部链接只回调插件，不由宿主自动打开。Dialog、SplitView 和键盘交互仍需在真实 IDE 中做一次人工观感验收，但自动化行为已覆盖。  

任务：未编号收尾（插件组件 Controller 完整支持）  
提交：工作区未提交  
IDE 修改：新增 `sdk.view.component.invoke` 公共命令、按完整 `ViewInstanceId` 隔离的 `ComponentMethodRegistry` 和稳定错误码；`PluginViewSurface` 挂载/切换/销毁及运行时 stop/restart/shutdown 均清理 host，且不在 dispose 后读取 Riverpod ref。全部组件接受通用可选 `id`，提供挂载状态、滚动可见、边界和焦点基础方法；TextField/NumberField、VirtualList/TreeView/PropertyGrid/DataTable、Tabs/Section/SplitView、Image/Video/Markdown、Menu/MenuBar/Dropdown/ContextMenu/Dialog 均接入真实宿主状态或 Flutter Controller。修复组件类型变化时错误复用 `GlobalKey`、清除选择回退到初始值、Dropdown 状态与幂等关闭、SDK 直接组件快照无法渲染等问题。  
SDK 修改：`Component.controller` 自动选择 17 类类型化 Controller，全部候选方法通过 `ViewModel.invoke_component` 发出实例级命令；快照中的直接或包装/嵌套 Component 均递归绑定和序列化；Row/Column/Flex/Grid/Wrap/Toolbar/Text/Icon/CodeBlock/Badge/Tooltip 等非交互组件补可选 `id`，可使用通用 Controller。  
协议变更：Envelope v1 不变；新增 `sdk.view.component.invoke`，payload 为 `{viewId, instanceId, componentId, method, arguments}`，共享 `protocol_v1_components.json` 已同步，SHA-256 为 `BAD78BDC6474100DFAC034296FC6D9DFEACA45E254F7182288434356411D2EFC`。错误码为 `view_not_mounted`、`component_not_found`、`method_not_supported`、`invalid_arguments`、`operation_failed`。  
验证命令：IDE scoped analyzer；`flutter test --concurrency=1 test/core/sdk test/features/plugin_view`；SDK Controller/components/view/fixture 定向 unittest、全量 unittest、`python -m compileall`、Black check；两仓库 fixture hash 与 `git diff --check`。  
验证结果：IDE analyzer 无问题，完整 core/sdk + plugin_view **361 tests 全部通过**；Controller/协议专项 **100 tests 全部通过**。SDK 定向 **62 tests 全部通过**，compileall/Black/fixture hash/diff check 通过；SDK 全量 **286 tests** 仍为 T00 已记录的旧 RFW/UI 基线 **4 failures + 5 errors**，无本轮新增失败。  
偏差/后续事项：ContextMenu 的右键/长按呈现仍由 `super_context_menu` 管理，命令式 `show` 使用宿主 Material popup；两条路径保持相同菜单数据与选择事件，但底层呈现机制不同。  

任务：T19（修复同一导航容器多 View 不可达）  
提交：工作区未提交  
IDE 修改：修复 `PluginViewHost` 只渲染导航容器第一个 View、导致已贡献的“设备变量”无法进入的问题。同一容器存在多个可见 View 时，宿主现在按 Manifest `order` 显示紧凑标签栏，支持 Material/插件资源图标；切换时使用各自的 `viewId` 和独立模型，并正确发送前一视图 closed、新视图 opened/focused 及 surface visibility 事件。容器级路由未指定 View 时仍选择首项，显式 View 路由保持原行为。  
SDK 修改：无；已安装的 `debug-enhanced` 1.5.0 已包含 `DeviceVariablesController`、`debug-enhanced.device-variables` 贡献和 `runtime.inspect` 权限，本次修复后该视图才在导航容器中真实可达。  
协议变更：无。  
验证命令：`flutter analyze --no-fatal-infos lib/pages/plugins/main.dart test/pages/plugins/plugins_legacy_behavior_test.dart`；`flutter test --concurrency=1 test/pages/plugins/plugins_legacy_behavior_test.dart`；SDK `python -m unittest tests.test_debug_enhanced_device_variables tests.test_debug_enhanced_outline`；`git diff --check`。  
验证结果：scoped analyzer 无问题；插件页面 10 项全部通过，新增测试确认从大纲切换后挂载的 `PluginViewSurface.viewId` 为 `debug-enhanced.device-variables`；SDK 大纲/设备变量控制器 24 项全部通过；diff 检查通过。  
偏差/后续事项：本次解决“设备变量 View 在插件导航中不可见/不可达”，不改变 T19 的后端状态。`DeviceRuntimeHost` 仍使用 `UnavailableRuntimeBackend`，因此进入视图后会显示安全不可用提示；真实设备值仍需无 CTRL-C 的协作式检查后端和设备验收，T19 保持 `[~]`。  

任务：T18/T19（调整大纲与设备变量标签页操作）  
提交：工作区未提交  
IDE 修改：无。  
SDK 修改：`debug_enhanced_plugin` 升级到 1.5.1；删除大纲 AppBar 中无意义的“在主编辑区打开大纲”，仅保留“在拓展区打开大纲”。设备变量 AppBar 新增“在主编辑区打开设备变量”和“在拓展区打开设备变量”，复用 `Tabs.create_view` 创建对应放置；宿主返回实例后创建独立 `VariableInspectorView`，立即同步当前变量快照、后续 patch、可见性和懒加载行为，创建失败时在现有视图显示错误状态。刷新操作保持不变。  
协议变更：无；复用 `sdk.tab.create_view` 和既有 View 实例协议。  
验证命令：SDK `python -m unittest tests.test_debug_enhanced_outline tests.test_debug_enhanced_device_variables tests.test_tab_api tests.test_packager_runtime`；`python -m compileall -q src examples/debug_enhanced_plugin`；Black；`git diff --check`；构建当前 SDK wheel并以 `--find-links` 打包 Windows 插件；读取 ZIP 校验版本、操作文本和内置 SDK。  
验证结果：相关 59 项全部通过，compileall/Black/diff 检查通过。产物 `E:\Can1425\pyrite-sdk\build\debug-enhanced-Windows.zip`，5,933,325 bytes，SHA-256 `3076E2074ADF946DB77139141FF54BE57FC437D9ED960DC36E328B7EB3550252`；包内版本为 1.5.1，不含“在主编辑区打开大纲”，包含两个设备变量标签页操作和当前 SDK。  
偏差/后续事项：操作与标签页实例链路已完成自动化验证；真实设备变量读取仍受 `UnavailableRuntimeBackend` 限制，T19 继续保持 `[~]`。  

任务：T20  
提交：工作区未提交  
IDE 修改：新增 `ContextKeyHost`、`CommandService`、`MenuResolver`、`PluginConfigStore` 与 `SdkConfiguration`；事件总线增加 `configuration.changed`；AppBar/右键/导航上下文合并 Manifest 菜单；插件详情页增加配置编辑；协议夹具与单测覆盖 when/enabled、持久化和 envelope。  
SDK 修改：新增 `Commands`/`Configuration` API，`Bridge` 分发 `ide.command.execute`；`debug_enhanced` 1.6.0 声明 refresh 命令/菜单与 `showPrivate` 配置，去掉仅刷新用的动态 AppBar 动作。  
协议变更：Envelope v1 不变；新增 `ide.command.execute`、`sdk.configuration.get/set/list` 与 topic `configuration.changed`。共享夹具 `protocol_v1_commands_configuration.json`。  
验证命令：`flutter test test/core/sdk/command_menu_config_test.dart test/core/sdk/protocol_v1_commands_configuration_test.dart test/pages/plugins`；`flutter analyze --no-fatal-infos`（T20 相关文件）；SDK `python -m unittest tests.test_commands_configuration tests.test_debug_enhanced_device_variables tests.test_debug_enhanced_outline tests.test_packager_runtime`。  
验证结果：IDE 定向与插件页 10 项通过；SDK 相关 65 项通过；analyzer 无问题。  
偏差/后续事项：命令面板 UI 仅完成解析与 execute 路径，未新增独立调色板界面；全局 IDE 设置页未合并插件配置（详情页 + API 已满足验收）。  

任务：T21  
提交：工作区未提交  
IDE 修改：每插件 control/view patch 双队列有界并按全局 sequence 批量 drain；大 JSON 使用 worker isolate；RPC deadline、自动 cancel、迟到响应丢弃和有界取消历史完整接线；View/节点/patch/log 预算及 metrics 接线。  
SDK 修改：Envelope 支持可选 deadline；可等待 handler 使用可取消 task；outbound queue 批量 drain；View 单 in-flight patch 自动拆分，隐藏视图恢复时 snapshot；日志按 UTF-8 64 KiB 分块。  
协议变更：Envelope v1 新增可选 `deadline`；新增 `ide.request.cancel`。两仓库 `protocol_v1_handshake.json` 同步 deadline/cancel 样例。  
验证命令：IDE scoped analyzer；`flutter test --concurrency=1` 跑 T21/run manager/view/store/event/protocol 组合；SDK compileall、44 项定向 unittest 与 303 项全量 unittest；两仓库 `git diff --check` 和 fixture 结构比较。  
验证结果：IDE T21/相关 63 项通过，analyzer 无问题；SDK 定向 44 项通过，compileall 通过；全量仍为既有 4 failures + 5 errors，无 T21 新增失败。  
偏差/后续事项：当前数值是首轮自动化预算，低端 Android 与桌面 frame-time/常驻内存仍需真实 benchmark 调优；监控与恢复接线已由 T22 完成。  

任务：T22  
提交：工作区未提交  
IDE 修改：插件会话 metrics 全量接线，插件详情和监控页展示状态、延迟、队列、流量、错误与 View 指标；输出按 pluginId/sessionId 分流；连续失败暂停事件/patch，恢复时对活动 View resync；提供 ping、恢复投递、插件重启和 Python runtime 重启；启动失败/意外退出采用 1s-60s 指数退避；runtime 重启清空旧 session/UI 状态并按需恢复当前可见插件和 onStartup service。  
SDK 修改：Bridge 增加 health pong、request task/event/page/view/command/asyncio 未捕获异常统一上报；dispose 取消任务、失败 pending callback、清空 events/commands/views/callback binding；delivery_paused 期间 View 只更新本地模型，等待 IDE 恢复后的 resync。  
协议变更：Envelope v1 不变；启用既有 `ide.health.ping`、`sdk.health.pong`、`sdk.runtime.report_error`，patch 暂停使用稳定错误码 `delivery_paused`。  
验证命令：IDE scoped `flutter analyze --no-fatal-infos`；`flutter test --concurrency=1` 跑 metrics/run manager/runtime host/output/store/event/View/插件页面组合；SDK `python -m compileall`、health/recovery/event/pending/transport/View/command 定向 unittest 和全量 unittest；两仓库 `git diff --check`。  
验证结果：IDE analyzer 无问题，T22/相关两组共 84 项通过；SDK 定向 66 项通过，compileall 通过；全量 308 项仍为既有 RFW/UI 基线 4 failures + 5 errors，无 T22 新增失败；diff check 无空白错误。  
偏差/后续事项：共享解释器内的 Python 异常与卡死停止可观察并可通过整体 runtime 重启恢复；native extension 进程级崩溃仍无法隔离。低端 Android/桌面监控页布局和真实插件故障恢复仍建议做一次人工验收。

任务：T23  
提交：工作区未提交  
IDE 修改：删除 `lib/pages/plugins/widgets/` 全部 RFW 组件（button/display/markdown/media/rfw_lib/selection/text_field）；插件列表与详情页不再打开旧插件 UI；`lib/features/plugin_view/` 的 `Video` 组件从 RFW 耦合的 `RfwVideoPlayer` 迁移为原生 `PluginVideoPlayer`（`video_player` 直驱，保留 play/pause/seek/volume/speed/loop/fullscreen 的 `VideoController` 契约），测试同步改为断言 `PluginVideoPlayer`；路由仅保留 `/plugins` 插件管理页。  
SDK 修改：删除 `src/pyrite_sdk/api/ui/`（含 sentence/、widgets/）、`interfaces/ui.py`、`utils/ui.py`、`utils/rfw_formatter.py`、`tools/utils/rfw_formatter.py`、`docs/api/websockets.md` 及 `file_counter_plugin`/`markdown_plugin`/`normal_plugin`/`ui_plugin` 示例；其余示例与三个模板全部为 Manifest v2 + native renderer（`native.form` 等）。  
协议变更：Envelope v1 不变；Manifest 校验保留 `rfwRendererUnsupported` 稳定错误码，`renderer = "rfw"`/`rfw.*` 直接拒绝，不进入运行时；旧插件数据被标记为不支持。  
验证命令：IDE `flutter analyze --no-fatal-infos`；`flutter test --concurrency=1 test/core/sdk test/pages/plugins` 及 `test/features/plugin_view/component_builder_test.dart`；SDK `python -m unittest discover -s tests -v`；两侧 `Select-String` 残留 RFW/legacy 全量扫描；两仓库 `git diff --check`。  
验证结果：IDE scoped analyzer 零问题，`core/sdk + pages/plugins` 串行 335 项、component_builder 28 项全部通过；SDK 全量 266 项 OK（原既有 RFW/UI 基线 4 failures + 5 errors 随删除一并消失）；IDE 全量 `flutter test` 剩余 10 项失败全部位于未修改的既有文件（git/ui_utils/raw_paste/widget 环境类问题，与 T23 无关）；扫描确认无残留 RFW import/路由/renderer token/SDK 导出；diff check 仅行尾转换提示。  
偏差/后续事项：Video 组件 fullscreen 为宿主内 Dialog 实现；Linux/macOS 仍未验收；T04/T05 保持既有阻塞状态，T24 四平台矩阵需在对应实际 runner 上执行。

任务：T24
提交：工作区未提交（IDE/SDK 与 pyrite-docs 均未提交）
IDE 修改：无代码改动（docs-only）；`dart format` 写入 4 个既有文件（`lib/core/i18n/i18n_key.dart`、`lib/core/sdk/plugin_event_bus.dart`、`test/core/sdk/clipboard_api_test.dart`、`test/core/sdk/device_runtime_host_test.dart`，均为 CRLF/LF 或尾随空白，无逻辑变更）。
SDK 修改：无。
协议变更：无。
文档（pyrite-docs）：按 T24 清单完成 Phase C/D——SDK 仓库内 5 份旧文档及空 `docs/api`、`docs/dev` 目录删除；`content/docs/sdk/` 9 个核心页重写，`sdk/api/` 24 页全部完成（index/view/native_views/components/tab/editor/document/file/board/persistence/serial/settings/configuration/path/environment/resources/clipboard/commands/events/message/dialog/runtime/theme/i18n/stubs），`sdk/meta.json`、`sdk/api/meta.json` 更新；`content/docs/ide/dev/` 新增 manifest、plugin-events、native-views、upgrade-guide 并重写 architecture、plugin-system；`ide/meta.json` 登记新页；`ide/user/plugins.mdx` 更新为 Manifest v2/单例解释器/generation 注意事项；`ide/user/settings.mdx` 与 `ide/index.mdx` 重写。
验证命令：`npx fumadocs-mdx`；`npm install` 补齐缺失依赖；`npm run types:check`（fumadocs-mdx + next typegen + tsc --noEmit）；`npm run build`（next build）；IDE `dart format`、`flutter analyze --no-fatal-infos lib test`、`flutter test`、`flutter build windows --release`、`flutter build apk --release`。
验证结果：pyrite-docs 在补齐 `@fuma-translate/react`、`mermaid` 依赖后 `types:check` 与 `build` 均通过（此前因 node_modules 缺失 `Cannot find module '@fuma-translate/react'` 失败，属预存环境问题，与内容无关）；IDE analyzer 无 error/warning（60 条既有 `use_build_context_synchronously` info）；`flutter test` 490 pass、10 fail，10 项失败全部为未修改的既有文件（`ui_utils_test`、`raw_paste_session_test`、`git_repository_service_test`、`widget_test` 的环境/引用类问题，与 T24 及重构无关）；Windows release `pyrite_ide.exe` 与 Android `app-release.apk`（119.9MB）构建成功。
偏差/后续事项：Linux/macOS 无实际 runner/CI，`flutter build linux/macos --release` 与 Linux/macOS 平台矩阵（PythonBridge 握手、插件启停、Data 插件、UI 视图、后台/恢复、10k 性能）需在对应平台或 CI 执行后关闭 `[!]`；Android 前后台/engine 重建场景沿用 T06 记录，仍需实机复核。

任务：T24 文档补充（插件作者自助参考）
提交：工作区未提交（pyrite-docs 内容编辑，IDE/SDK 无改动）
IDE 修改：无
SDK 修改：无
协议变更：无
文档（pyrite-docs）：应"很多地方写得太简略、概念需详细解释、继续开发插件系统也要看"的要求，围绕"`renderer` 必填但组件树可覆盖"补充概念层内容。`sdk/ui-plugins.mdx` 新增「两种渲染路径」：渲染器驱动（`views.form/tree` 等 facade + Manifest 声明 renderer）vs 组件树覆盖（`view.snapshot()` 直接发送组件树，完全忽略 renderer token），并附选择建议表；`sdk/api/view.mdx` 新增「视图模型的两类形态」+「同步协议」流程图（snapshot → patch → ack/nack/resync，含 `ViewProtocolError` 本地抛出说明）；`sdk/api/index.mdx` 扩写「回调模式」（成功/失败双路径、同步与异步、Bridge 线程）与「错误体系」（`SdkApiError` 子类表 + 本地异常表 + 边界 Callout）；`sdk/lifecycle.mdx` 扩写激活状态机（installed/enabled/activating/active/deactivating/failed）、激活事件按需激活、启动时序流程图（握手 → start 钩子 → active）、当前宿主仅发送 start/dispose 钩子的说明、会话与代数（session_id/generation 三件套校验 → `InvalidPluginContextError`）、线程模型（asyncio 事件循环线程回调 + `bridge.push()` 线程安全 + BridgeOutputRouter 输出路由）；`sdk/plugin-types.mdx` 增加激活方式与常驻语义、决策流程；`sdk/api/components.mdx` 新增「工作原理」声明式数据管线与事件回调查找流程。
验证命令：`npx fumadocs-mdx`；`npm run types:check`（fumadocs-mdx + next typegen + tsc --noEmit）；`npm run build`（next build）。
验证结果：`npx fumadocs-mdx` 生成成功；`types:check` 通过（含 TypeScript 类型检查）；`next build` 编译成功、195 页静态生成完成，无内容相关错误。
偏差/后续事项：全部编辑以源码为准（python_runtime_host/activation_manager/bridge/context/errors/view/components/plugin），未改协议与代码；`on_pause`/`on_resume` 已如实标注"宿主当前不分发"。Linux/macOS 验收仍保持 T24 原 `[!]` 状态。

任务：T24 文档补充（二轮：移除破坏性升级指南 + 详细化/可读化）
提交：工作区未提交（pyrite-docs 内容编辑，IDE/SDK 无改动）
IDE 修改：无
SDK 修改：无
协议变更：无
文档（pyrite-docs）：
- **移除破坏性生成指南**：删除 `ide/dev/upgrade-guide.mdx`（破坏性升级指南），并从 `ide/meta.json`、`ide/dev/plugin-system.mdx` 清除引用；旧版（WebSocket + RFW）升级内容整体不再提供。
- **教程式实战演练**：新增 `sdk/tutorial.mdx`（从零写一个 `device-console` Ui 插件），按"清单 → 激活 → 视图 → 命令/菜单 → 配置 → 事件 → 打包"完整链路给出带注释的 `plugin.toml` 与 `__main__.py`，强调回调异步心智模型，并附调试技巧表与"步骤 → 概念 → 参考页"对照清单。
- **概念可视化**：`sdk/lifecycle.mdx` 增补激活状态机 Mermaid 图；`sdk/api/index.mdx` 增补 API 调用往返 sequence 图（调用 → Bridge → 宿主 → data/error 双路径回调）；`sdk/api/events.mdx` 增补订阅与投递链路 sequence 图（含 filter/delivery 过滤）。
- **完整注释样例**：`ide/dev/manifest.mdx` 的「完整示例」改写为逐字段注释版（含 icons、location/order、menus、commands、configuration、when），并附运行时配置读写示例。
- **FAQ / 排错指南**：新增 `sdk/troubleshooting.mdx`——错误码速查表、manifest 校验错误表、权限被拒、视图不显示、ViewProtocolError/负载上限、回调不执行、会话与运行时失效（InvalidPluginContextError/StaleReferenceError/RuntimeUnavailableError/StaleRevisionError/TransportClosedError）、插件卡死重启运行时、单例解释器全局状态污染，以及"快速定位流程"决策树。
- **API 速查索引**：`sdk/api/index.mdx` 新增「常用任务速查」"我想做什么 → 用哪个模块"表。
- 导航接线：`sdk/meta.json` 登记 `tutorial` 与 `troubleshooting`；`sdk/index.mdx` 的 Cards 与 `quick-start.mdx` 的「下一步」补充新页面链接。
验证命令：`npx fumadocs-mdx`；`npm run types:check`（fumadocs-mdx + next typegen + tsc --noEmit）；`npm run build`（next build）。
验证结果：`npx fumadocs-mdx` 生成成功；`types:check` 通过（含 TypeScript 类型检查与 Mermaid 组件引用校验）；`next build` 编译成功、198 页静态生成完成（原 195 − 移除 upgrade-guide 1 + 新增 tutorial/troubleshooting 2），无内容相关错误。
偏差/后续事项：示例代码中的 `get_file_list` 回调 `entries` 形状与命令处理器签名均以源码为准；Mermaid 图使用既有 `components/mdx/mermaid` 组件（index.mdx 已在用），未新增依赖。Linux/macOS 验收仍保持 T24 原 `[!]` 状态。

每完成一个任务，在此追加：

```text
任务：Txx
提交：<commit 或工作区说明>
IDE 修改：...
SDK 修改：...
协议变更：...
验证命令：...
验证结果：...
偏差/后续事项：...
```