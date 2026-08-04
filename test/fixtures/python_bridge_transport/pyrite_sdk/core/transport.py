from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator, Awaitable, Callable
from enum import Enum
from typing import Any

RawMessage = str | bytes
ClientHandler = Callable[[Any], Awaitable[None]]


class TransportState(str, Enum):
    CONNECTING = "connecting"
    READY = "ready"
    CLOSING = "closing"
    CLOSED = "closed"
    FAILED = "failed"


class TransportClosedError(ConnectionError):
    pass


class Transport(ABC):
    @property
    @abstractmethod
    def state(self) -> TransportState:
        raise NotImplementedError

    @abstractmethod
    async def start(self, handler: ClientHandler) -> None:
        raise NotImplementedError

    @abstractmethod
    def messages(self, client: Any) -> AsyncIterator[RawMessage]:
        raise NotImplementedError

    @abstractmethod
    async def send(self, client: Any, message: RawMessage) -> None:
        raise NotImplementedError

    @abstractmethod
    async def wait_closed(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def close(self) -> None:
        raise NotImplementedError
