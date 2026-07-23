<div align="center">

# <image src="assets/icons/app_icon.webp" height="30" width="30"/> PyriteIDE

<a href="https://github.com/pyrite-project/pyrite-ide/blob/main/LICENSE">
<img src="https://img.shields.io/badge/license-AGPL-green?style=for-the-badge&labelColor=333333&color=4CAF50" alt="License"/>
</a>
<a href="https://github.com/pyrite-project/pyrite-ide/stargazers">
<img src="https://img.shields.io/github/stars/pyrite-project/pyrite-ide.svg?style=for-the-badge&logo=github&labelColor=333333&color=FFD700" alt="GitHub Stars"/>
</a>
<a href="https://flutter.dev">
<img src="https://img.shields.io/badge/Platform-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Platform"/>
</a>



一个现代化，强大，且跨平台的 MicroPython IDE
A modern and powerful MicroPython IDE designed for cross-platform use


#### [官方网站](https://pyrite.flowecho.org) | [Release 下载](https://github.com/pyrite-project/pyrite-ide/releases)

#### [QQ 用户交流群 Pyrite Project #1](https://qm.qq.com/q/hQviIqr0gU)


![banner](assets/docs/banner.webp)

</div>

PyriteIDE 将本地项目、MicroPython 开发板与日常开发工具整合进同一个工作区：从编写代码、连接设备，到同步文件、运行脚本与管理版本，无需在多个工具之间反复切换。

## 主要特性

1. **编辑器与语言服务** — 多标签编辑、会话恢复、可配置 LSP，以及面向不同开发板组合的 MicroPython Stubs Layers。
2. **完整的设备工作流** — 通过 USB 串口连接 REPL，在编辑器中运行或中断脚本，并在本地与开发板之间上传、下载文件；覆盖冲突会在执行前确认。
3. **内置 Git 工作区** — 查看状态与差异、暂存更改、创建提交、管理分支和历史记录，并完成 Pull / Push 等常用操作。
4. **可控的插件系统** — 使用内置 Python Runtime 运行 UI、Service 与 Data 插件，支持 ZIP 安装、权限声明与监控，以及主题、语言包和 Stubs 等数据贡献。
5. **响应式跨平台体验** — 桌面端提供本地终端与串口能力，Android 侧针对 USB 串口和开发板文件操作优化布局。

## 支持平台

项目的 GitHub Actions 会在 `v*` 标签发布时构建以下目标：

| 平台 | 发布产物 | 主要能力 |
| --- | --- | --- |
| Windows | ZIP | 桌面终端、USB 串口、完整工作区 |
| macOS | App ZIP | 桌面终端、USB 串口、完整工作区 |
| Linux | tar.gz | 桌面终端、USB 串口、完整工作区 |
| Android | 分 ABI APK | 移动布局、USB 串口、开发板文件 |

## 快速开始

### 下载发行版

前往 [Releases](https://github.com/pyrite-project/pyrite-ide/releases)，下载与你的平台对应的构建产物并解压或安装。

### 从源码构建

准备好 Git、Flutter `3.44.4` 及目标平台所需的开发工具。原生组件的构建还需要 Rust 工具链。

```bash
git clone --recursive https://github.com/pyrite-project/pyrite-ide.git
cd pyrite-ide
flutter pub get
```

将 `windows` 替换为 `linux`、`macos` 或可用的 Android 设备 ID。若仓库不是通过 `--recursive` 克隆，请先执行：

```bash
git submodule update --init --recursive
```

首先请设置 `SERIOUS_PYTHON_SITE_PACKAGES` 环境变量，请将 `...` 处替换为项目根目录：

```bash
export SERIOUS_PYTHON_SITE_PACKAGES=".../assets/python_runtime_boot"
```

针对你的**目标平台**，打包 `python_runtime_boot.zip`，这里以 `Linux` 为例：

```bash
dart run serious_python:main package "assets/python_runtime_boot" --platform Linux --asset "assets/python_runtime_boot.zip" --verbose
```

运行命令开始编译：

```bash
flutter build linux --release --verbose
```

其中的 `--release` 和 `--verbose` 均为可选参数，须特别注意，若目标平台为 `Android` 或 `MacOS`，须传入 `--no-tree-shake-icons` 参数

## 插件开发

PyriteIDE 插件以 ZIP 分发，并通过 `plugin.toml` 声明类型、平台与权限：

| 类型 | 适用场景 |
| --- | --- |
| `ui` | 页面、控件与用户交互 |
| `service` | 后台任务、设备监听与同步服务 |
| `data` | 主题、语言包与 MicroPython Stubs |

插件运行时、生命周期、SDK API、权限模型和打包方式见插件开发文档，具体内容正在撰写，请关注通知 。

## 参与开发

欢迎通过 [Issues](https://github.com/pyrite-project/pyrite-ide/issues) 报告问题或提出建议，也欢迎提交 Pull Request。提交前请运行：

```bash
dart format .
flutter analyze --no-fatal-infos lib test
```

项目中没有引入 Riverpod 注解或路由生成器，推荐使用传统写法：

## 开源许可

PyriteIDE 基于 [GNU Affero General Public License v3.0](./LICENSE) 开源。
