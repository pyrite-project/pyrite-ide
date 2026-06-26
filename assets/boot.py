import sys

def _save_original_snapshot():
    """保存 Python 启动时的原始 sys.path 和 sys.modules 键集。
    这个函数应该在没有任何第三方模块被导入之前调用。
    给后续操作提供恢复点
    """
    if not hasattr(sys, '_runtime_original_sys_path'):
        sys._runtime_original_sys_path = list(sys.path) # type: ignore
    if not hasattr(sys, '_runtime_original_modules_keys'):
        sys._runtime_original_modules_keys = set(sys.modules.keys()) # type: ignore

_save_original_snapshot()