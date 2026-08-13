# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PyriteIDE is a cross-platform MicroPython IDE built with Flutter. It integrates local project management, MicroPython device connectivity, code editing with LSP support, file transfer, Git version control, and a Python-based plugin system into a unified workspace.

## Architecture

### Core Structure

- **`lib/main.dart`**: Application entry point, initializes persistence, Python runtime, and plugin systems
- **`lib/app/`**: App-level configuration (routing with `go_router`, theme setup, main app widget)
- **`lib/core/`**: Shared infrastructure
  - **`core/sdk/`**: Plugin system SDK (~60 files) — plugin manager, activation, permissions, transport, component registry, event bus, document host, runtime host, and API surface
  - **`core/services/`**: Core services (~60 files) — file management, Git integration, serial/REPL, editor state, LSP, persistence, message system, periodic tasks
  - **`core/models/`**: Data models (editor state, device status, settings, file metadata)
  - **`core/constants/`**: Theme definitions, window config, navigation bar setup
  - **`core/i18n/`**: Internationalization providers
- **`lib/pages/`**: Feature screens (editor, file browser, Git UI, device tools, plugins, settings, welcome)
- **`lib/features/`**: Reusable feature modules (`edit_core`, `function_page`, `plugin_view`, `window`)
- **`lib/shared/`**: Shared UI components (tabbed view, tree widgets, context menus)

### Local Dependencies

- **`python_runtime/`**: Submodule containing `serious_python` — the embedded Python runtime for executing plugins
- **`flserial/`**: Submodule for USB serial communication with MicroPython boards
- **`flutter_pty/`**: Submodule providing terminal/PTY support for desktop platforms
- **`xterm.dart/`**: Submodule for terminal emulator UI
- **`super_tree/`**: Submodule for tree view components

All submodules must be initialized with `git submodule update --init --recursive` before building.

### Plugin System

PyriteIDE's plugin system runs Python code through an embedded runtime (`serious_python`). Plugins are distributed as ZIP archives with a `plugin.toml` manifest declaring type (`ui`, `service`, or `data`), platform compatibility, and required permissions. The SDK (under `lib/core/sdk/`) exposes APIs for file access, editor control, serial communication, UI rendering, events, and persistence. Plugin transport uses a JSON-RPC bridge between Dart and Python.

## Build & Development

### Prerequisites

- Flutter `3.44.4` (exact version used by CI)
- Rust toolchain (for native components in `code_forge`, `super_native_extensions`)
- Git with submodules initialized
- Platform-specific: Linux requires `libmpv-dev mpv`, macOS requires `automake libtool`

### Common Commands

```bash
# Install dependencies (includes local path packages and submodules)
flutter pub get

# Package Python runtime for target platform (required before first build)
# Set environment variable first:
export SERIOUS_PYTHON_SITE_PACKAGES="<absolute-path-to-repo>/assets/python_runtime_boot"
# Then package for your platform (Windows, Linux, Darwin, or Android):
dart run serious_python:main package "assets/python_runtime_boot" --platform Linux --asset "assets/python_runtime_boot.zip" --verbose

# Run the app (desktop or Android device)
flutter run -d windows   # or linux, macos, android device ID

# Build release package
# For Android/macOS: add --no-tree-shake-icons
flutter build windows --release --verbose
flutter build linux --release --verbose
flutter build macos --release --no-tree-shake-icons --verbose
flutter build apk --release --split-per-abi --no-tree-shake-icons --verbose

# Regenerate code (after Riverpod annotations or route changes)
dart run build_runner build --delete-conflicting-outputs

# Lint and analyze (same as CI)
dart format .
flutter analyze --no-fatal-infos lib test

# Run tests
flutter test
```

### Python Runtime Packaging

Before building for any platform, the Python runtime must be packaged into `assets/python_runtime_boot.zip`. Set the `SERIOUS_PYTHON_SITE_PACKAGES` environment variable to the absolute path of `assets/python_runtime_boot`, then run `dart run serious_python:main package` with the correct `--platform` flag (Windows, Linux, Darwin, or Android). This step is automated in CI but must be done manually for local builds.

## State Management

The project uses Riverpod for state management. Providers are defined inline (not using code generation for most providers). Key provider patterns:

- `lib/core/sdk/plugin_manager_provider.dart`: Plugin lifecycle and installation
- `lib/core/services/editor/tabbed_view_controller_provider.dart`: Editor tab state
- `lib/core/services/file/file_provider.dart`: File tree and local workspace
- `lib/core/services/serial/serial_provider.dart`: Device connection state
- `lib/core/services/git/git_repository_service.dart`: Git operations

## Key Subsystems

### Editor & LSP

The editor uses a tabbed interface with session persistence. Language server support is configurable through `lib/core/services/pylsp/` and integrates with MicroPython stubs layering system (stubs are data contributions from plugins).

### Device Workflow

USB serial connectivity via `flserial` allows REPL interaction, script execution, and file transfer between the local workspace and MicroPython boards. Conflict detection and user confirmation are built into upload/download operations.

### Git Integration

Built-in Git UI (under `lib/pages/git/`) uses `git2dart` for status, diff, staging, commit, branch management, and remote operations. Diff display and editing are in `lib/core/services/git/`.

### Terminal

Desktop platforms use `flutter_pty` for native terminal support with `xterm.dart` rendering. The terminal is integrated into the workspace but does not run on Android.

## Coding Conventions

- Follow `package:flutter_lints/flutter.yaml` rules
- Use `dart format .` for consistent formatting
- File naming: `snake_case.dart`
- Types: `PascalCase`, members: `lowerCamelCase`
- Provider files: suffix with `_provider.dart`
- Avoid Riverpod code generation (this project uses traditional provider definitions)
- No route generation imports — routes are manually defined in `lib/app/routes.dart`

## Testing

Tests are in `test/` and mirror the structure of `lib/`. Focus areas: file operations, Git behavior, plugin system, serialization, and UI regressions. Run `flutter test` and `flutter analyze --no-fatal-infos lib test` before committing.

## Platform Notes

- **Android/macOS builds**: Must pass `--no-tree-shake-icons` to `flutter build`
- **Linux runtime**: Requires `libmpv-dev` and `mpv` installed
- **Windows**: No special build flags beyond Python runtime packaging
- **Submodules**: Always keep local dependencies in sync with `pubspec.yaml` path references
