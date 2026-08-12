# Arch Linux packaging

This directory contains the two standalone AUR package definitions:

- `pyride`: builds PyriteIDE from the tagged source and pinned submodules.
- `pyride-bin`: installs the official prebuilt Linux release bundle.

Each subdirectory is intended to become the root of its corresponding AUR Git
repository. Generate `.SRCINFO` after changing a PKGBUILD:

```sh
makepkg --printsrcinfo > .SRCINFO
```

The source package pins the CPython and dart-bridge artifacts consumed by
serious_python so the native CMake build does not download them implicitly.
Flutter packages are resolved from the committed `pubspec.lock`. Both packages
install the relocatable application bundle under `/usr/lib/pyride` and expose
the `pyride` command through `/usr/bin`. The source package uses `flutter-bin`
because the split AUR `flutter` package currently trails the minimum version
used by upstream CI.
