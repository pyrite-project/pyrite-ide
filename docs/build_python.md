$env:SERIOUS_PYTHON_SITE_PACKAGES = "E:\Can1425\pyrite_ide\build\__pypackages__"

# Android
dart run serious_python:main package python --platform Android --requirements "--pre" --requirements "-rpython/requirements.txt" --requirements "--find-links=python/android_wheel/" --asset "assets/android/python.zip" --verbose

# Windows
dart run serious_python:main package python --platform Windows --requirements "--pre" --requirements "-rpython/requirements.txt" --asset "assets/windows/python.zip" --verbose

# Linux
dart run serious_python:main package python --platform Linux --requirements "--pre" --requirements "-rpython/requirements.txt" --asset "assets/linux/python.zip" --verbose

# macOS
dart run serious_python:main package python --platform macOS --requirements "--pre" --requirements "-rpython/requirements.txt" --asset "assets/macos/python.zip" --verbose

对于桌面平台，请注意检查构建产物 python.zip 中是否存在 __pypackages__，若没有，请执行以下操作。（此处示例，开发平台为 Windows，目标平台为 Windows）

然后前往 `project_root\build`，将 `__pypackages__` 添加进构建产物 python.zip 中

在 Android 平台上，`serial_python` 会根据环境变量 `SERIOUS_PYTHON_SITE_PACKAGES` 构建应用，这导致 debug 的时候非常尴尬，大概率会遇到 `SERIOUS_PYTHON_SITE_PACKAGES environment variable is not set.`，此时要么直接设置系统环境变量，要么在有该环境变量的上下文中构建应用

目前我选择后者 搭配 `adb logcut` 进行调试，未来看看有没有更好的办法吧