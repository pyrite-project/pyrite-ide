import os
import sys

def setup_sys_path():
    module_paths_str = os.environ.get('RUNTIME_MODULE_PATHS')
    replace = os.environ.get('RUNTIME_REPLACE_MODULE_PATHS') == '1'

    if not module_paths_str and not replace:
        return

    # 将字符串拆分为列表
    module_paths = module_paths_str.split("::") if module_paths_str else []

    if replace:
        if hasattr(sys, '_runtime_original_sys_path'):
            sys.path[:] = list(sys._runtime_original_sys_path)

        # 2. 清除所有不在原始键集中的第三方模块
        if hasattr(sys, '_runtime_original_modules_keys'):
            original_keys = sys._runtime_original_modules_keys
            for mod in list(sys.modules.keys()):
                if mod not in original_keys:
                    del sys.modules[mod]
    # 反向迭代，顺序传入
    for path in reversed(module_paths):
        if not path:
            continue
        # 转换为绝对路径，去除末尾斜杠
        normalized = os.path.abspath(path).rstrip(os.sep)
        if normalized not in sys.path:
            sys.path.insert(0, normalized)

    # print("[serious_python] sys.path adjusted:", file=sys.stderr)
    # for p in sys.path:
    #     print("  ", p, file=sys.stderr)

setup_sys_path()