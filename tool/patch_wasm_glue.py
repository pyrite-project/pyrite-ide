"""Applies the wasm-bindgen glue adjustment the web editor core needs.

flutter_rust_bridge's web thread pool initializes its Web Workers with
`wasm_bindgen({module_or_path, memory})`, but the stock `wasm-bindgen` 0.2.92
glue feeds that argument straight into `WebAssembly.instantiate`, which rejects
a plain object with a TypeError. `__wbg_init` therefore unwraps `module_or_path`
first.

Nothing else about the memory is patched. `wasm_bindgen::memory()` must keep
returning the real `WebAssembly.Memory`, because `js_sys::TypedArray::to_vec`
goes through `wasm_bindgen::memory().buffer()` to copy a Dart payload into the
wasm heap; handing it a stand-in makes every call that takes arguments fail
with "RangeError: offset is out of bounds".

The web build deliberately routes every call through the calling thread instead
of the worker pool (see the note on `init_app` in
`code_forge/rust/src/api/editor.rs`), so the pool never spawns a worker and the
memory is never posted anywhere.

Usage: python tool/patch_wasm_glue.py <path to code_forge.js>
"""
import sys
from pathlib import Path

INIT_BEFORE = """async function __wbg_init(input) {
    if (wasm !== undefined) return wasm;
"""

INIT_AFTER = """async function __wbg_init(input) {
    if (wasm !== undefined) return wasm;

    // Patched by tool/patch_wasm_glue.py: flutter_rust_bridge initializes its
    // Web Workers with `{ module_or_path, memory }` rather than the bare
    // module, and `memory` is unused outside the main thread.
    if (input !== null && typeof input === 'object' && 'module_or_path' in input) {
        input = input.module_or_path;
    }
"""

MEMORY_MARKER = "Patched by tool/patch_wasm_glue.py: the Web Worker"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    glue = Path(sys.argv[1])
    source = glue.read_text(encoding="utf-8")

    if INIT_AFTER in source:
        print(f"{glue} is already patched")
        return 0
    if MEMORY_MARKER in source:
        print(
            f"tool/patch_wasm_glue.py: {glue} still carries the obsolete "
            "__wbindgen_memory patch; regenerate it from the wasm.",
            file=sys.stderr,
        )
        return 1
    if INIT_BEFORE not in source:
        print(
            f"tool/patch_wasm_glue.py: __wbg_init not found in {glue}; "
            "the wasm-bindgen output shape changed, update this script.",
            file=sys.stderr,
        )
        return 1

    glue.write_text(source.replace(INIT_BEFORE, INIT_AFTER, 1), encoding="utf-8")
    print(f"patched {glue}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())