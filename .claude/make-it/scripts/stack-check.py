#!/usr/bin/env python3
"""Where would this app's stack reach and keep its data? One rule, two callers.

Reads `docker compose config --format json` on stdin (settings already resolved: the Compose file, `.env`, env files).

  stack-check.py local
      /resume-it's live pass ("settings point at this machine", deadcode.md section 5's "Settings first" bullet):
      a database, queue or cache address must be a Compose service, localhost or 127.0.0.1.
  stack-check.py copy PROJECT
      /make-it's write test, before it starts the temporary copy named PROJECT: every address the copy would use --
      database, queue, cache, storage or any other service -- must be one of the copy's own Compose services, or the
      copy's own published port on this machine. localhost, 127.0.0.1 and host.docker.internal are the person's own
      machine, so they are refused like any outside host. The copy's volumes must be its own (not external, not
      fixed-name), and no service may mount a writable folder of this computer.

Exit 0 and print nothing: it may start. Exit 1 and print one plain reason: it must not. Anything unknown or
unreadable is a refusal. It never prints a setting's value: a host name and a setting's NAME only (a URL can hold
a password).
"""
import json
import re
import sys

URL = re.compile(r"([A-Za-z][A-Za-z0-9+.\-]*)://(?:[^/?#\s,]*@)?(\[[^\]]+\]|[^:/?#\s,@]*)(?::(\d+))?")
KEYED = re.compile(r"(?i)\b(?:host|hostaddr|server|data source)\s*=\s*(?:tcp:)?([A-Za-z0-9._\-]+)")
PLAIN = re.compile(r"\s*(\[[^\]]+\]|[A-Za-z0-9._\-]+)(?::(\d+))?\s*")
ADDR_NAME = re.compile(r"(HOST|HOSTNAME|SERVER|SERVERS|BROKER|BROKERS|ADDR|ADDRESS)$")
URL_NAME = re.compile(r"(URL|URI|DSN|ENDPOINT|CONNECTION|CONNECTION_STRING|CONN_STR)$")
STORE_NAME = re.compile(r"DB|DATABASE|POSTGRES|PG|MYSQL|MARIA|MONGO|REDIS|CACHE|QUEUE|RABBIT|AMQP|KAFKA|BROKER|SQL")
WEB = {"http", "https", "ws", "wss"}
THIS_MACHINE = {"localhost", "127.0.0.1", "::1", "[::1]", "host.docker.internal", "gateway.docker.internal",
                "host.containers.internal"}
BIND_ALL = {"0.0.0.0", "::", "[::]"}


def addresses(name, value):
    """(scheme, host, port) for each address in one setting. host None: it should hold an address and can't be read."""
    value = "" if value is None else str(value).strip()
    if not value:
        return []
    urls = [(m.group(1).lower(), m.group(2).lower(), m.group(3)) for m in URL.finditer(value)]
    if urls:
        return [u for u in urls if u[1]]          # sqlite:///./file.db has no host: a file in the container
    keyed = [("", h.lower(), None) for h in KEYED.findall(value)]
    if keyed:
        return keyed
    if ADDR_NAME.search(name):
        out = []
        for part in value.split(","):
            m = PLAIN.fullmatch(part)
            if not m:
                return [("", None, None)]
            out.append(("", m.group(1).lower(), m.group(2)))
        return out
    if URL_NAME.search(name) and not value.startswith(("/", ".")):
        return [("", None, None)]
    return []


def refuse(reason):
    print(reason)
    sys.exit(1)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("local", "copy") or (mode == "copy" and len(sys.argv) != 3):
        refuse("the app's settings can't be checked")
    try:
        cfg = json.load(sys.stdin)
        services = cfg["services"]
        names = set()
        for key, svc in services.items():
            names.add(key.lower())
            names.update(str(svc[k]).lower() for k in ("container_name", "hostname") if svc.get(k))
        published = {str(p.get("published")) for svc in services.values() for p in (svc.get("ports") or []) if p.get("published")}
        settings = []
        for svc in services.values():
            env = svc.get("environment") or {}
            if isinstance(env, list):
                env = dict(e.split("=", 1) if "=" in e else (e, "") for e in env)
            settings += list(env.items())
        volumes = cfg.get("volumes") or {}
    except Exception:
        refuse("the app's settings can't be read")

    if mode == "copy":
        project = sys.argv[2]
        for key, vol in volumes.items():
            if (vol or {}).get("external") or not str((vol or {}).get("name", "")).startswith(project + "_"):
                refuse(f"the copy would share your app's storage (the volume {key} is not the copy's own)")
        for key, svc in services.items():
            for m in svc.get("volumes") or []:
                if m.get("type") not in ("volume", "tmpfs") and not m.get("read_only"):
                    refuse(f"the copy would share your app's storage (a folder of this computer is mounted into {key})")

    for name, value in settings:
        for scheme, host, port in addresses(name, value):
            if host is None:
                if mode == "copy":
                    refuse(f"the address in {name} can't be read, so it may be outside this app's own copy")
                continue
            if host in names:
                continue
            if mode == "local":
                store = (scheme and scheme not in WEB) or (not scheme and STORE_NAME.search(name))
                if store and host not in ("localhost", "127.0.0.1"):
                    refuse(f"your settings point at {host}")
                continue
            if not scheme and host in BIND_ALL:
                continue                          # an address to listen on, not one to reach
            if host in THIS_MACHINE and port and port in published:
                continue                          # the copy's own published port
            refuse(f"your settings point at {host}, which is not part of this app's own copy")
    sys.exit(0)


main()
