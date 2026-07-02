# PyriteIDE 插件与 SDK 开发文档

本文档面向 PyriteIDE 插件作者，说明插件项目结构、插件类型、生命周期、权限、SDK API、数据贡献和打包发布流程。

## 阅读顺序

1. [快速开始](./01-quick-start.md)
2. [插件清单 plugin.toml](./02-manifest.md)
3. [插件类型与生命周期](./03-plugin-types-lifecycle.md)
4. [权限模型](./04-permissions.md)
5. [SDK API](./05-sdk-apis.md)
6. [数据贡献 Contribution](./06-data-contributions.md)
7. [打包与发布](./07-packaging.md)
8. [排错](./08-troubleshooting.md)

## 核心概念

- UI 插件：有页面、有交互，继承 `UiPlugin`。
- Service 插件：后台常驻任务，继承 `ServicePlugin`。
- Data 插件：只贡献数据，运行一次后退出，继承 `DataPlugin`。
- Contribution：由 IDE 持久管理的数据贡献，例如主题、语言包、MicroPython stubs。
- Runtime Registration：插件运行期间临时注册的数据，插件停止后失效。

## 示例插件位置

SDK 示例位于：

```text
E:\Can1425\pyrite-sdk\examples
```

常用示例：

- `normal_plugin`：UI 插件示例
- `service_plugin`：后台服务插件示例
- `theme_plugin`：主题数据插件示例
- `i18n_plugin`：语言包数据插件示例
- `stubs_plugin`：MicroPython stubs 数据插件示例
