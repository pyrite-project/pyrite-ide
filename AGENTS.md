# Repository Guidelines

## Project Structure & Module Organization
PyriteIDE is a Flutter desktop/mobile app. Application code lives under `lib/`: `app/` contains app setup and routing, `core/` contains models, constants, SDK, and services, `features/` holds platform or feature glue, `pages/` contains screen-level UI, and `shared/` contains reusable widgets. Tests are in `test/`, currently grouped by area such as `test/git/`. Static assets are in `assets/` and are declared in `pubspec.yaml`; documentation is in `docs/`. Platform runners live in `android/`, `linux/`, `macos/`, and `windows/`. The bundled Python runtime is under `python_runtime/`.

## Build, Test, and Development Commands
- `flutter pub get`: install Dart and Flutter dependencies.
- `dart run build_runner build --delete-conflicting-outputs`: regenerate Riverpod, route, or other generated Dart code after annotation changes.
- `flutter analyze`: run the analyzer and Flutter lint rules.
- `flutter test`: run unit and widget tests in `test/`.
- `flutter run -d windows`: run locally on Windows; replace `windows` with an available device when needed.
- `flutter build windows --release` or `flutter build apk --release`: create release builds. CI packages Python assets first with `dart run serious_python:main package python ...`.

## Coding Style & Naming Conventions
Use the default Dart style: two-space indentation, `dart format .`, trailing commas where they improve formatting, `PascalCase` for classes/widgets, `camelCase` for members, and `snake_case.dart` filenames. Keep provider files and service files descriptive, for example `git_status_summary_provider.dart`. The project uses `package:flutter_lints/flutter.yaml`; prefer fixing analyzer warnings over suppressing them.

## Testing Guidelines
Use `flutter_test` for unit and widget coverage. Name files `*_test.dart` and mirror the feature or service path when practical, such as `test/git/git_repository_service_test.dart`. Add focused tests for changed models, services, persistence, routing, and UI behavior. Run `flutter analyze` and `flutter test` before submitting.

## Commit & Pull Request Guidelines
Recent history uses short imperative commits, often with conventional prefixes such as `feat:`, `fix:`, and `build:`. Keep subjects specific, for example `fix: avoid git native plugin crashes`. Pull requests should include a concise description, linked issue when applicable, test results, and screenshots or screen recordings for visible UI changes.

## Security & Configuration Tips
Do not commit secrets, local signing files, generated release artifacts, or machine-specific IDE state. Keep `pubspec.lock` in sync with dependency changes. When cloning or updating, initialize submodules recursively so `python_runtime/` dependencies are available.
