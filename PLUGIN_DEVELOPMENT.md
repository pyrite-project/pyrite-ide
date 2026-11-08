# PyriteIDE 插件开发

PyriteIDE 的插件是一段 Python 程序，运行在 IDE 自带的 CPython 运行时里，通过 JSON-RPC 与宿主通信。插件以 `.pyrix` 包分发，用 `plugin.toml` 声明类型、平台、权限和贡献点。

> 本文面向插件作者。宿主的实现细节在 `lib/core/sdk/`。文中所有字段名、权限名和入口约定都取自当前代码，与 `test/fixtures/manifest_v2/` 下的 fixtures 一致。

## 1. 最小插件

```
my-plugin/
├── plugin.toml        # Manifest，必须有
├── __main__.py        # 入口，文件名固定
└── resources/         # 可选：图标、stubs、语言包等
```

入口文件名是固定的 `__main__.py`——宿主按这个名字启动插件，`plugin.toml` 里没有「入口路径」字段。缺这个文件时宿主会直接报 `Plugin entry point does not exist`。

`plugin.toml` 的最小内容（Manifest v2）：

```toml
manifest_version = 2
id = "com.example.hello"
name = "Hello"
version = "0.1.0"
type = "ui"
protocol_version = 1
activation_events = ["onCommand:com.example.hello.greet"]
permissions = ["ui.view", "editor.read"]
platforms = ["windows", "linux", "macos", "android"]

[[contributes.commands]]
id = "com.example.hello.greet"
title = "Say Hello"
```

把目录打包成 zip，把后缀改成 `.pyrix`，就能在「插件」页安装。v1 manifest 仍然能装，但新插件请用 v2。

## 2. 插件类型

| 类型 | 什么时候用 | 典型例子 |
| --- | --- | --- |
| `ui` | 需要界面：面板、对话框、编辑器旁的视图 | 引脚图、串口示波器、代码片段面板 |
| `service` | 不需要界面，在后台持续工作 | 设备监听、自动同步、通知转发 |
| `data` | 只贡献数据，不执行逻辑 | 主题、语言包、MicroPython stubs、LSP 服务器配置 |

`data` 插件同样会被激活，但它的生命周期只到「把数据交给 IDE」为止。

## 3. 生命周期

插件连接后宿主依次发送：

1. **initialize** — 宿主告诉插件 `protocolVersion`、`sdkVersion`、支持的 capability 和被授予的权限。插件在这一步校验宿主版本，返回自己的 metadata。
2. **initialized** — 握手完成，此后插件可以主动发请求。注意：握手完成之前发任何请求，严格的实现会直接退出进程。
3. **activate** — 到达激活事件时触发一次。插件在这里注册命令、创建视图、恢复状态。
4. **deactivate** — 插件被停用、重载或 IDE 退出时触发。必须释放所有资源：定时器、后台线程、文件句柄、已注册的监听。
5. **dispose / 传输关闭** — 进程内的会话结束。

任何一步抛异常，宿主会记录到插件监控页并把插件标为 `error`，不会拖垮 IDE。

### 激活事件

格式是 `事件:目标`：

| 事件 | 触发时机 |
| --- | --- |
| `onStartup` | IDE 启动时（`service` 插件常用） |
| `onView:<view-id>` | 该视图第一次被打开 |
| `onCommand:<command-id>` | 该命令第一次被调用 |
| `onLanguage:<language-id>` | 打开对应语言的文件 |

插件不应假设自己一定被激活——用户可能禁用了它，或者它在不匹配的平台上运行。

## 4. 权限

`permissions` 是一个**扁平的字符串数组**，形如 `资源.动作`：

```toml
permissions = [
  "editor.read",
  "editor.write",
  "file.read",
  "board.read",
  "serial.read",
  "settings.read",
]
```

可用的资源与动作：

| 资源 | 动作 | 说明 |
| --- | --- | --- |
| `file` | read / write | 本地工作区文件 |
| `board` | read / write | 开发板文件系统 |
| `editor` | read / write / keys | 编辑器文本、选区、**按键接管** |
| `serial` | read / write | 串口与 REPL |
| `persistence` | read / write | 插件私有储物柜 |
| `tab` | create / manage | 标签页 |
| `settings` | read / write | IDE 设置 |
| `data` | read / write | 主题、语言包、stubs 等数据贡献 |
| `dialog` | show | 文件/目录选择器 |
| `runtime` | inspect | 设备运行时变量检查 |
| `ui` | view / notify / navigate | 视图、通知、路由 |

写权限隐含读权限。每次调用都会写一条权限审计记录，用户在「插件 → 权限监控」里能看到。

没有权限时宿主返回 `permission_denied`，不会静默失败——插件应当把这类错误展示给用户，而不是吞掉。

### 按键接管

`editor.keys` 是唯一能**抑制编辑器自身行为**的权限。插件拿到它之后可以：

```python
await sdk.editor.capture_keys(["tab", "escape"])
# 这期间 Tab 不再插入缩进，按键事件被转发给插件
await sdk.editor.release_keys(["tab"])   # 不带参数表示全部释放
```

宿主把按键事件作为 `ide.editor.key` 推给插件，插件必须在 **300ms** 内回复 `{"handled": true/false}`。超时视为「未处理」，按键丢失但编辑器保持可用。

插件停止时所有按键自动归还，但主动释放仍是必要的：用户不会喜欢一个看不见的插件抢走 Tab。

## 5. 常用 API

SDK 按域组织，完整清单见 `lib/core/sdk/api/`。下面是最常用的几组。

```python
# 编辑器
text = await sdk.editor.get_text()
await sdk.editor.insert_text("print('hello')")
await sdk.editor.set_selection(0, 5)

# 文档（含 LSP 符号）
doc = await sdk.editor.document.get()
symbols = await sdk.editor.document.symbols()
await sdk.editor.document.reveal(line=12, column=0)

# 文件
items = await sdk.file.get_dir_list()
content = await sdk.file.read_file("main.py")
await sdk.file.write_file("main.py", "print(1)")

# 开发板
await sdk.board.write_file("/main.py", content)
listing = await sdk.board.get_dir_list("/")

# 串口 / REPL
status = await sdk.serial.get_status()

# 持久化（插件私有）
await sdk.persistence.set("state", {"counter": 3})
state = await sdk.persistence.get("state")

# 消息与 UI
await sdk.message.show("已同步", level="info")
await sdk.view.open(view_id="main")
```

规则：

- **所有 API 都是异步的**。阻塞调用会冻结宿主的 UI 线程。
- 返回值是 JSON 可序列化的结构；不要返回自定义对象。
- 出错时抛的异常带宿主给的错误信息，可以直接展示给用户。

## 6. UI 插件

UI 插件的界面由**组件树**描述，不是直接操作 Flutter widget。插件返回一棵 JSON 组件树，宿主负责渲染：

```python
await sdk.view.open(view_id="my-plugin.pins", title="引脚图")
await sdk.view.patch("my-plugin.pins", {
    "type": "column",
    "children": [
        {"type": "text", "text": "GPIO 状态"},
        {"type": "button", "text": "刷新", "command": "my-plugin.refresh"},
    ],
})
```

宿主支持的组件类型与属性见 `lib/core/sdk/component_schema.dart`，渲染实现见 `lib/features/plugin_view/`。**schema 会随宿主升级**：插件在 `initialize` 时应当检查宿主报告的 `sdkVersion`，对不支持的组件降级，而不是直接崩掉。

也可以用 `native.*` 渲染器接管布局（例如 `native.outline`、`native.variableInspector`），此时插件只提供数据，宿主用内置行布局渲染——这比手搓组件树省事，也更贴合 IDE 的视觉。

## 7. 数据插件

`data` 插件通过 `contributes` 注册数据：

| 贡献 | 效果 |
| --- | --- |
| theme | 增加一套编辑器/终端/界面主题 |
| locale | 增加一种界面语言 |
| stubs | 增加 MicroPython stubs 层（供自动补全与类型检查） |
| lspServer | 增加一个语言服务器配置（stdio 或 WebSocket） |

Stubs 层的关键是 `metadata`：**IDE 的「自动探测层级」按板卡芯片家族匹配 profile id、label、path 和 metadata 里的字符串**（`esp32s3` / `esp32` / `rp2040` / `stm32` …）。写 `metadata = { board = "ESP32-S3" }` 就能让插上 S3 时自动选中这套 stubs；写不出可识别的名字，自动探测就不会选它——宁可不动，也不会乱猜。

自动探测的匹配规则在 `lib/core/services/editor/lsp_stubs_auto_detect.dart`，有单测覆盖。

## 8. 调试

- 插件的 stdout/stderr 进入「插件 → 监控 → 输出」。
- 未捕获异常连同 traceback 记录到监控页的会话指标里。
- 每次权限调用都会留痕，用来确认「是不是我没权限」。
- 开发时最快的方式是改完文件后在插件页点「重启」，而不是卸载重装。

## 9. 打包与兼容性

- 目前只支持从本地 `.pyrix` 文件安装，没有在线市场。
- Manifest 必须声明 `manifest_version`、`id`、`version`、`type`；`id` 在同一 IDE 里唯一。
- 宿主升级可能改变 SDK 表面。插件应当：
  - 在 `initialize` 里比对 `protocolVersion` 与 `sdkVersion`；
  - 对不认识的 capability 降级而不是报错；
  - 把「宿主版本过低」清楚地告诉用户。

## 10. 常见错误

| 现象 | 原因 |
| --- | --- |
| 安装后不出现 | `platforms` 没包含当前平台，或 manifest 校验失败（插件页会显示原因） |
| 启动即报 entry point 不存在 | 缺少 `__main__.py`，或它不在包根目录 |
| 命令点了没反应 | 没有对应的 `onCommand:` 激活事件，或命令没在 `contributes.commands` 里注册 |
| 提示 permission_denied | `permissions` 里没写对应资源.动作；注意 `editor.keys` 是独立动作 |
| Tab 键突然不灵 | 插件 capture 了 `tab` 却没有释放 |
| 视图白屏 | 组件树里有 schema 不认识的 `type`；检查 `sdkVersion` |
| 自动 stubs 没生效 | profile 的 id/label/path/metadata 里没有可识别的芯片名 |

---

示例插件见 `test/fixtures/plugins/` 与 `test/fixtures/manifest_v2/`。
