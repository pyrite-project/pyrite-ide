import sys

def _save_original_snapshot():
    if not hasattr(sys, '_runtime_original_sys_path'):
        sys._runtime_original_sys_path = list(sys.path) # type: ignore
    if not hasattr(sys, '_runtime_original_modules_keys'):
        sys._runtime_original_modules_keys = set(sys.modules.keys()) # type: ignore

_save_original_snapshot()