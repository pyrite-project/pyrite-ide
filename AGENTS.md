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

## Commit & Pull Request Guidelines

Git history follows Conventional Commit-style messages, for example `feat: add more widgets for RFW`, `fix: fix the stdio issue`, and `build!: modify application information`. Use `!` for breaking changes. PRs should include a short summary, linked issue when applicable, tested commands, affected platforms, and screenshots for visible UI changes.

## Security & Configuration Tips

Do not commit secrets, local device paths, signing keys, or generated user data. Keep submodules and local path dependencies in sync with `pubspec.yaml`, and verify runtime packaging before changing packaged runtime assets.
