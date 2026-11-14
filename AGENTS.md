# Repository Guidelines

## Project Structure & Module Organization

PyriteIDE is a Flutter desktop/mobile app. Main Dart code lives in `lib/`: `lib/main.dart` boots the app, `lib/app/` contains app setup and routing, `lib/core/` contains shared models, services, SDK APIs, constants, and persistence, and `lib/pages/` contains feature screens such as editor, files, git, plugins, settings, and device tools. Reusable UI and feature modules are under `lib/shared/` and `lib/features/`.

Tests live in `test/` and generally mirror the affected area, for example `test/core/services/file/...` or `test/git/...`. Static assets are in `assets/`, docs are in `docs/`, and platform runners are in `android/`, `linux/`, `macos/`, and `windows/`. Local path dependencies include `flserial/`, `python_runtime/`, and `third_party/`.

## Build, Test, and Development Commands

- `flutter pub get`: install dependencies, including local path packages.
- `dart run build_runner build --delete-conflicting-outputs`: regenerate Riverpod and route builder outputs after annotation changes.
- `flutter analyze --no-fatal-infos lib test`: run the analyzer with the same scope used by CI.
- `flutter test`: run unit and widget tests.
- `flutter run -d windows`: run locally on Windows; replace with `linux`, `macos`, or an Android target as needed.
- `flutter build windows --release`: build a release package. CI also packages `assets/python_runtime_boot.zip` with `dart run serious_python:main package ...`.

## Coding Style & Naming Conventions

Use Dart defaults: two-space indentation, `dart format .`, `PascalCase` for types, `lowerCamelCase` for members, and `snake_case.dart` file names. This repo uses `package:flutter_lints/flutter.yaml`; fix analyzer findings rather than suppressing them. Keep provider files clearly named, such as `*_provider.dart`.

## Testing Guidelines

Use `flutter_test` for unit and widget coverage. Name test files `*_test.dart`, place them under the closest matching `test/` directory, and cover serialization, file operations, git behavior, plugin widgets, and UI regressions when touched. Run tests and analysis before opening a PR.

## Logging & Diagnostics

Route logging through `lib/core/services/logging/app_log.dart` instead of `debugPrint`. `AppLog.d` is per-transaction detail and only runs in debug/profile builds; `AppLog.i` marks an operation boundary; `AppLog.w` / `AppLog.e` are problems and are the only levels appended to the log file. Collapse loops with `AppLog.progress` (one line per 10% step) or `AppLog.atMostEvery` (one line per time window) rather than emitting per chunk or per frame.

Problem records must stand on their own, because the console is gone after a restart. Every warning and error written to the file carries the error object, the stack, and the last 40 lines emitted before it (`--- last N events ---`), which is what makes a failure readable without asking the user to replay their steps. `AppLog.e` falls back to `StackTrace.current` when the throw site has no stack, flushes to disk immediately (rate limited to once per second), and `AppLog.flushSync` is called before `exit`. Uncaught errors reach the same sink through `FlutterError.onError` and `PlatformDispatcher.instance.onError`.

- Log file: `%LOCALAPPDATA%\PyriteIDE\logs\app.log` on Windows, `~/.pyrite_ide/logs/app.log` elsewhere, rotating to `app.log.old` at 2 MB.
- Each launch opens with `AppLog.session` (`session start os=... mode=... bootMs=...`), so a run that never fails still leaves a trace.
- Disable the file with `--dart-define=PYRITE_LOG_NO_FILE=true`; tests never write it. Dump whole SDK frames with `--dart-define=PYRITE_SDK_TRACE=true` (clipped to 4 KB per frame).
- A `catch` that swallows an error silently must say why in a comment, or log it — pick `AppLog.d` for expected control flow and `AppLog.w` when the failure changes behaviour in a way a bug report would need.

## Commit & Pull Request Guidelines

Git history follows Conventional Commit-style messages, for example `feat: add more widgets for RFW`, `fix: fix the stdio issue`, and `build!: modify application information`. Use `!` for breaking changes. PRs should include a short summary, linked issue when applicable, tested commands, affected platforms, and screenshots for visible UI changes.

## Security & Configuration Tips

Do not commit secrets, local device paths, signing keys, or generated user data. Keep submodules and local path dependencies in sync with `pubspec.yaml`, and verify runtime packaging before changing packaged runtime assets.
