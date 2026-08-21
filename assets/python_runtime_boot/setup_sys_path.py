"""Helpers for constructing a plugin import path.

The persistent runtime applies this list through its thread-local import
context. Importing this module must not mutate process-global ``sys.path``.
"""

import os


def runtime_module_paths(module_paths=(), plugin_path=None):
    """Return normalized paths in import precedence order."""
    result = []
    for value in module_paths:
        if not value:
            continue
        normalized = os.path.abspath(value).rstrip(os.sep)
        if normalized and normalized not in result:
            result.append(normalized)
    if plugin_path:
        normalized = os.path.abspath(plugin_path).rstrip(os.sep)
        if normalized and normalized not in result:
            result.insert(0, normalized)
    return result
