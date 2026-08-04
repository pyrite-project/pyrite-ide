from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import sys
import traceback
import types

import dart_bridge


channels = json.loads(os.environ["PYRITE_IDE_TEST_CHANNELS"])
status_port = int(channels[0]["port"])


def _load_sdk_transport():
    sdk_src = os.environ["PYRITE_IDE_TEST_SDK_SRC"]
    package_root = os.path.join(sdk_src, "pyrite_sdk")
    core_root = os.path.join(package_root, "core")
    package = types.ModuleType("pyrite_sdk")
    package.__path__ = [package_root]
    core_package = types.ModuleType("pyrite_sdk.core")
    core_package.__path__ = [core_root]
    sys.modules["pyrite_sdk"] = package
    sys.modules["pyrite_sdk.core"] = core_package

    for name in ("transport", "dart_bridge_transport"):
        qualified_name = f"pyrite_sdk.core.{name}"
        spec = importlib.util.spec_from_file_location(
            qualified_name,
            os.path.join(core_root, f"{name}.py"),
        )
        module = importlib.util.module_from_spec(spec)
        sys.modules[qualified_name] = module
        spec.loader.exec_module(module)
    return sys.modules[
        "pyrite_sdk.core.dart_bridge_transport"
    ].DartBridgeTransport


async def main() -> None:
    DartBridgeTransport = _load_sdk_transport()
    transports = [
        DartBridgeTransport.from_environment(queue_size=16),
        *[
            DartBridgeTransport(
                int(channel["port"]),
                str(channel["label"]),
                queue_size=16,
            )
            for channel in channels[1:]
        ],
    ]

    def make_handler(transport: DartBridgeTransport):
        async def handler(client) -> None:
            async for message in transport.messages(client):
                if message == b"__close_pyrite_transport__":
                    transport.close()
                    return
                await transport.send(client, message)

        return handler

    for transport in transports:
        await transport.start(make_handler(transport))

    dart_bridge.send_bytes(status_port, b"__pyrite_transport_ready__")

    await asyncio.gather(
        *(transport.wait_closed() for transport in transports)
    )


try:
    asyncio.run(main())
except BaseException:
    dart_bridge.send_bytes(
        status_port,
        ("__pyrite_transport_error__" + traceback.format_exc()).encode(),
    )
    raise
