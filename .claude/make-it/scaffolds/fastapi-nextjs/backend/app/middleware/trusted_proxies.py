"""Take the visitor's address from X-Forwarded-For, but only from a proxy this app trusts.

Every browser request reaches the backend through a proxy -- the same-origin frontend (compose) or
an ingress (Kubernetes) -- so the address that connects is the proxy's. TRUSTED_PROXIES names the
proxies whose X-Forwarded-For is believed: IP addresses, networks (10.0.0.0/8) or host names
(`frontend`, the compose service). Host names are looked up again every REFRESH_SECONDS, so a proxy
that restarts with a new address is trusted again within that time; a name that does not resolve
trusts no one until it does. Empty (the default) trusts no proxy. "*" is refused: it would let any
caller choose the address the app records.

The header is read by uvicorn's ProxyHeadersMiddleware: the right-most address that is not a trusted
proxy is the visitor, so an address a caller wrote in front of the one a trusted proxy appended is
never taken. entrypoint.sh starts uvicorn with --no-proxy-headers, so this is the only place that
reads it.
"""

import asyncio
import ipaddress
import socket
import time

from starlette.types import ASGIApp, Receive, Scope, Send
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

REFRESH_SECONDS = 10.0


def _is_address(entry: str) -> bool:
    try:
        ipaddress.ip_network(entry, strict=False)
    except ValueError:
        return False
    return True


async def _lookup(name: str) -> set[str]:
    try:
        infos = await asyncio.get_running_loop().getaddrinfo(name, None, type=socket.SOCK_STREAM)
    except OSError:
        return set()
    return {info[4][0] for info in infos}


class TrustedProxyHeaders:
    def __init__(self, app: ASGIApp, trusted: str) -> None:
        entries = [entry.strip() for entry in trusted.split(",") if entry.strip()]
        if "*" in entries:
            raise ValueError("TRUSTED_PROXIES must name the proxies; '*' would believe every caller")
        self.app = app
        self.addresses = [entry for entry in entries if _is_address(entry)]
        self.names = [entry for entry in entries if not _is_address(entry)]
        self._found: list[str] = []
        self._next_lookup = 0.0
        self._inner = ProxyHeadersMiddleware(app, trusted_hosts=self.addresses)

    async def _refresh(self) -> None:
        self._next_lookup = time.monotonic() + REFRESH_SECONDS
        found: set[str] = set()
        for name in self.names:
            found |= await _lookup(name)
        if sorted(found) != self._found:
            self._found = sorted(found)
            self._inner = ProxyHeadersMiddleware(self.app, trusted_hosts=self.addresses + self._found)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if self.names and scope["type"] != "lifespan" and time.monotonic() >= self._next_lookup:
            await self._refresh()
        await self._inner(scope, receive, send)
