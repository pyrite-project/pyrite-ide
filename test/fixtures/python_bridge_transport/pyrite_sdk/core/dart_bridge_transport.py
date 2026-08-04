from __future__ import annotations

import asyncio
import os
import weakref
from collections.abc import AsyncIterator
from typing import Any

from .transport import (
    ClientHandler,
    RawMessage,
    Transport,
    TransportClosedError,
    TransportState,
)

DART_PORT_ENV = "PYRITE_IDE_PLUGIN_BRIDGE_PORT"
DART_CHANNEL_LABEL_ENV = "PYRITE_IDE_PLUGIN_BRIDGE_LABEL"
_CLOSE_MESSAGE = object()


class _QueueOverflowError(RuntimeError):
    pass


class _RestartRegistry:
    def __init__(self, bridge_module: Any):
        self._channels: weakref.WeakValueDictionary[
            str, DartBridgeTransport
        ] = weakref.WeakValueDictionary()
        bridge_module.add_session_restart_handler(self._handle_restart)

    def add(self, transport: DartBridgeTransport) -> None:
        existing = self._channels.get(transport.channel_label)
        if existing is not None and existing is not transport:
            raise RuntimeError(
                f"Duplicate dart bridge channel label: {transport.channel_label}"
            )
        self._channels[transport.channel_label] = transport

    def remove(self, transport: DartBridgeTransport) -> None:
        existing = self._channels.get(transport.channel_label)
        if existing is transport:
            self._channels.pop(transport.channel_label, None)

    def _handle_restart(self, ports: dict[str, int]) -> None:
        for label, transport in list(self._channels.items()):
            port = ports.get(label)
            if port is not None:
                transport._schedule_port_update(port)


_restart_registries: weakref.WeakKeyDictionary[Any, _RestartRegistry] = (
    weakref.WeakKeyDictionary()
)


def _restart_registry(bridge_module: Any) -> _RestartRegistry:
    registry = _restart_registries.get(bridge_module)
    if registry is None:
        registry = _RestartRegistry(bridge_module)
        _restart_registries[bridge_module] = registry
    return registry


class DartBridgeTransport(Transport):
    def __init__(
        self,
        port: int,
        channel_label: str,
        *,
        queue_size: int = 50,
        bridge_module: Any = None,
    ):
        if port <= 0:
            raise ValueError("dart bridge port must be positive")
        if not channel_label:
            raise ValueError("dart bridge channel label must not be empty")
        if queue_size <= 0:
            raise ValueError("dart bridge queue size must be positive")

        if bridge_module is None:
            import dart_bridge as bridge_module

        self._bridge = bridge_module
        self._port = port
        self.channel_label = channel_label
        self.queue_size = queue_size
        self._state = TransportState.CLOSED
        self._loop: asyncio.AbstractEventLoop | None = None
        self._queue: asyncio.Queue[RawMessage | object] | None = None
        self._closed_event: asyncio.Event | None = None
        self._handler_task: asyncio.Task[None] | None = None
        self._client = object()
        self._closed = False
        self._native_handler = self._receive_native
        self._registry = _restart_registry(self._bridge)

    @classmethod
    def from_environment(
        cls,
        *,
        queue_size: int = 50,
        bridge_module: Any = None,
    ) -> DartBridgeTransport:
        raw_port = os.environ.get(DART_PORT_ENV)
        channel_label = os.environ.get(DART_CHANNEL_LABEL_ENV)
        if raw_port is None:
            raise RuntimeError(f"{DART_PORT_ENV} is required")
        if channel_label is None or not channel_label:
            raise RuntimeError(f"{DART_CHANNEL_LABEL_ENV} is required")
        try:
            port = int(raw_port)
        except ValueError as error:
            raise RuntimeError(f"{DART_PORT_ENV} must be an integer") from error
        return cls(
            port,
            channel_label,
            queue_size=queue_size,
            bridge_module=bridge_module,
        )

    @property
    def port(self) -> int:
        return self._port

    @property
    def state(self) -> TransportState:
        return self._state

    async def start(self, handler: ClientHandler) -> None:
        if self._closed:
            raise TransportClosedError("DartBridgeTransport is closed")
        if self._state == TransportState.READY:
            return

        self._state = TransportState.CONNECTING
        self._loop = asyncio.get_running_loop()
        self._queue = asyncio.Queue(maxsize=self.queue_size)
        self._closed_event = asyncio.Event()
        try:
            self._registry.add(self)
            self._bridge.set_enqueue_handler_func(
                self._port,
                self._native_handler,
            )
            self._handler_task = asyncio.create_task(handler(self._client))
            self._state = TransportState.READY
        except Exception:
            self._registry.remove(self)
            self._state = TransportState.FAILED
            raise

    def _receive_native(self, payload: bytes) -> None:
        loop = self._loop
        if self._closed or loop is None or loop.is_closed():
            return
        message = bytes(payload)
        loop.call_soon_threadsafe(self._enqueue_on_loop, message)

    def _enqueue_on_loop(self, message: bytes) -> None:
        queue = self._queue
        if self._closed or queue is None:
            return
        try:
            queue.put_nowait(message)
        except asyncio.QueueFull:
            self._state = TransportState.FAILED
            self._replace_oldest(
                _QueueOverflowError(
                    f"Dart bridge queue for {self.channel_label} is full"
                )
            )

    def _replace_oldest(self, message: object) -> None:
        queue = self._queue
        if queue is None:
            return
        try:
            queue.get_nowait()
            queue.task_done()
        except asyncio.QueueEmpty:
            pass
        try:
            queue.put_nowait(message)
        except asyncio.QueueFull:
            pass

    async def _messages(self, client: Any) -> AsyncIterator[RawMessage]:
        if client is not self._client:
            raise ValueError("Unknown dart bridge client")
        queue = self._queue
        if queue is None:
            raise RuntimeError("DartBridgeTransport has not started")
        while True:
            message = await queue.get()
            try:
                if message is _CLOSE_MESSAGE:
                    return
                if isinstance(message, Exception):
                    raise message
                if isinstance(message, (str, bytes)):
                    yield message
            finally:
                queue.task_done()

    def messages(self, client: Any) -> AsyncIterator[RawMessage]:
        return self._messages(client)

    async def send(self, client: Any, message: RawMessage) -> None:
        if self._closed or self._state in {
            TransportState.CLOSING,
            TransportState.CLOSED,
        }:
            raise TransportClosedError("DartBridgeTransport is closed")
        if client is not self._client:
            raise ValueError("Unknown dart bridge client")
        payload = message.encode("utf-8") if isinstance(message, str) else bytes(message)
        self._bridge.send_bytes(self._port, payload)

    async def wait_closed(self) -> None:
        event = self._closed_event
        if event is None:
            return
        await event.wait()

    def _schedule_port_update(self, port: int) -> None:
        loop = self._loop
        if self._closed or loop is None or loop.is_closed():
            return
        loop.call_soon_threadsafe(self._update_port_on_loop, int(port))

    def _update_port_on_loop(self, port: int) -> None:
        if self._closed or port <= 0 or port == self._port:
            return
        self._bridge.set_enqueue_handler_func(self._port, None)
        self._port = port
        self._bridge.set_enqueue_handler_func(
            self._port,
            self._native_handler,
        )

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._state = TransportState.CLOSING
        self._registry.remove(self)
        self._bridge.set_enqueue_handler_func(self._port, None)

        loop = self._loop
        if loop is None or loop.is_closed():
            self._state = TransportState.CLOSED
            return
        loop.call_soon_threadsafe(self._finish_close_on_loop)

    def _finish_close_on_loop(self) -> None:
        self._replace_oldest(_CLOSE_MESSAGE)
        self._state = TransportState.CLOSED
        if self._closed_event is not None:
            self._closed_event.set()
