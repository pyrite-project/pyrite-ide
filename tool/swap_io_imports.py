"""Rewrites dart:io / path_provider imports to the platform facades.

Run once: python tool/swap_io_imports.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

IO_FACADE = "package:pyrite_ide/core/platform/pyrite_io.dart"
PATHS_FACADE = "package:pyrite_ide/core/platform/pyrite_paths.dart"

IO_RE = re.compile(r"^import\s+['\"]dart:io['\"](\s+show\s+[^;]+)?;\s*$")
PP_RE = re.compile(
    r"^import\s+['\"]package:path_provider/path_provider\.dart['\"]"
    r"(\s+(?:show|as)\s+[^;]+)?;\s*$"
)

EXCLUDE = {
    "lib/core/services/serial/serial_provider.dart",
    "lib/core/services/editor/desktop_terminal_provider.dart",
    "lib/core/sdk/python_bridge_plugin_transport.dart",
    "lib/core/services/serial/web_repl_socket.dart",
}


def insert_sorted(lines: list[str], import_line: str) -> list[str]:
    """Inserts import_line into the package-import block, alphabetically."""
    target = import_line.split("'")[1]
    first_package = None
    last_package = None
    for i, line in enumerate(lines):
        m = re.match(r"^import\s+['\"](package:[^/'\"]*/)", line)
        if m:
            if first_package is None:
                first_package = i
            last_package = i
    if first_package is None:
        # No package imports: insert after the last dart: import, or top.
        anchor = 0
        for i, line in enumerate(lines):
            if line.startswith("import") or line.startswith("export"):
                anchor = i + 1
        return lines[:anchor] + [import_line] + lines[anchor:]

    for i in range(first_package, last_package + 1):
        m = re.match(r"^import\s+['\"]([^'\"]+)['\"]", lines[i])
        if m and m.group(1) > target:
            return lines[:i] + [import_line] + lines[i:]
    return lines[: last_package + 1] + [import_line] + lines[last_package + 1 :]


def process(path: Path) -> str | None:
    rel = path.relative_to(ROOT).as_posix()
    if rel in EXCLUDE:
        return None
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    needs_io = any(IO_RE.match(line) for line in lines)
    needs_paths = any(PP_RE.match(line) for line in lines)
    if not (needs_io or needs_paths):
        return None
    lines = [line for line in lines if not IO_RE.match(line)]
    lines = [line for line in lines if not PP_RE.match(line)]
    if needs_io:
        lines = insert_sorted(lines, f"import '{IO_FACADE}';\n")
    if needs_paths:
        lines = insert_sorted(lines, f"import '{PATHS_FACADE}';\n")
    path.write_text("".join(lines), encoding="utf-8")
    return rel


def main() -> None:
    changed = []
    for path in sorted(LIB.rglob("*.dart")):
        result = process(path)
        if result:
            changed.append(result)
    print(f"updated {len(changed)} files")
    for rel in changed:
        print(f"  {rel}")


if __name__ == "__main__":
    sys.exit(main())
