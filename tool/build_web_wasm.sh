#!/usr/bin/env bash
# Regenerates the editor wasm asset consumed by the Flutter web build.
#
# flutter_rust_bridge's web loader requests "<webPrefix><stem>.js" and
# "<webPrefix><stem>_bg.wasm", then reads the init function from the global
# `wasm_bindgen`. Only the `no-modules` target of wasm-bindgen emits that
# global, so the target is not interchangeable here.
#
# The build deliberately does NOT enable `+atomics`. A shared (SharedArrayBuffer
# backed) memory would only be needed for flutter_rust_bridge's Web Worker
# thread pool, and producing one requires rebuilding std with -Z build-std.
# Instead every call is dispatched on the calling thread; see the note on
# `init_app` in code_forge/rust/src/api/editor.rs.
#
# Usage: bash tool/build_web_wasm.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate_dir="$root/code_forge/rust"
out_dir="$root/web/pkg"

cd "$crate_dir"
cargo build --release --target wasm32-unknown-unknown

mkdir -p "$out_dir"
wasm-bindgen \
  --target no-modules \
  --no-modules-global wasm_bindgen \
  --out-dir "$out_dir" \
  --out-name code_forge \
  target/wasm32-unknown-unknown/release/code_forge.wasm

python "$root/tool/patch_wasm_glue.py" "$out_dir/code_forge.js"

echo "wasm asset written to $out_dir"