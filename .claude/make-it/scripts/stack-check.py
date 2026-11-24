#!/usr/bin/env python3
"""Where would this app's stack reach and keep its data? Two callers.

Reads `docker compose config --format json` on stdin (settings already resolved: the Compose file, `.env`, env files).

  stack-check.py local
      /resume-it's live pass ("settings point at this machine", deadcode.md section 5's "Settings first" bullet):
      a database, queue or cache address must be a Compose service, localhost or 127.0.0.1.
  stack-check.py copy PROJECT
      /make-it's write test, before it starts the temporary copy named PROJECT. The copy is used only on make-it's
      STANDARD set-up: an allow-list of what the scaffolds define, never a list of unsafe shapes. Every one of
      these must hold, or the set-up is "not standard" and the write test is not run:
        - every service is one the scaffolds define, with no network_mode, extra_hosts, links or external_links;
        - one network, the project's own (not external, no fixed name), and no service on any other;
        - every volume is the project's own named volume; no folder of this computer is mounted;
        - every address-valued setting is one the scaffolds know, is read for certain, and points at one of the
          copy's own services or at the copy's own published port on this machine;
        - no cloud storage or outside service is named by its keys.

Exit 0 and print nothing: it may start. Exit 1 and print the first reason in plain words: it must not. Anything
unknown or unreadable is a refusal. It never prints a setting's value: a host name or a setting's NAME at most (a
URL can hold a password), and for an address it can't read for certain, the NAME only.

The three sets below are what the two scaffolds' own files define; scripts/test-live-checks-write-copy.sh derives
them from those files and fails when they differ.
"""
import json
import re
import sys

# --- make-it's standard set-up (fastapi-nextjs and nextjs-fullstack) ---
SCAFFOLD_SERVICES = {"frontend", "backend", "app", "db", "mock-oidc"}
SCAFFOLD_BINDS = set()                      # container paths the scaffolds mount a folder of this computer on: none
KNOWN_ADDRESSES = {"DATABASE_URL", "OIDC_ISSUER_URL", "OIDC_EXTERNAL_URL", "FRONTEND_URL", "BACKEND_URL",
                   "BACKEND_INTERNAL_URL", "NEXTAUTH_URL", "MOCK_OIDC_EXTERNAL_BASE_URL",
                   "MOCK_OIDC_INTERNAL_BASE_URL", "CRIBL_STREAM_URL", "TRUSTED_PROXIES"}
ADDRESS_NAME = re.compile(r"(URL|URI|DSN|ENDPOINT|HOST|HOSTNAME|SERVER|SERVERS|BROKER|BROKERS|ADDR|ADDRESS|PROXIES"
                          r"|CONNECTION|CONNECTION_STRING)$")
CLOUD_NAME = re.compile(r"^(AWS_|S3_|GCS_|GCP_|GOOGLE_CLOUD_|GOOGLE_APPLICATION_CREDENTIALS|AZURE_STORAGE|R2_|MINIO_"
                        r"|SUPABASE_|FIREBASE_|CLOUDINARY_)|BUCKET|BLOB|SAS_TOKEN")
SERVICE_OPTIONS = ("network_mode", "extra_hosts", "links", "external_links")
# an address read for certain: scheme://[user[:password]@]host[:port][/path], plain characters only; or host[,host...]
STRICT_URL = re.compile(r"[a-z][a-z0-9+.\-]*://(?:[A-Za-z0-9._~%\-]+(?::[A-Za-z0-9._~%\-]*)?@)?([A-Za-z0-9.\-]+)"
                        r"(?::(\d+))?(?:[/?#][^\s@\\]*)?")
STRICT_HOSTS = re.compile(r"[A-Za-z0-9.\-]+(?::\d+)?(?:,[A-Za-z0-9.\-]+(?::\d+)?)*")

# --- the `local` rule ---
URL = re.compile(r"([A-Za-z][A-Za-z0-9+.\-]*)://(?:[^/?#\s,]*@)?(\[[^\]]+\]|[^:/?#\s,@]*)(?::(\d+))?")
STORE_NAME = re.compile(r"DB|DATABASE|POSTGRES|PG|MYSQL|MARIA|MONGO|REDIS|CACHE|QUEUE|RABBIT|AMQP|KAFKA|BROKER|SQL")
WEB = {"http", "https", "ws", "wss"}


def refuse(reason):
    print(reason)
    sys.exit(1)


def settings_of(services):
    out = []
    for svc in services.values():
        env = svc.get("environment") or {}
        if isinstance(env, list):
            env = dict(e.split("=", 1) if "=" in e else (e, "") for e in env)
        out += [(str(k), "" if v is None else str(v).strip()) for k, v in env.items()]
    return out


def check_local(services):
    names = {k.lower() for k in services}
    for name, value in settings_of(services):
        for m in URL.finditer(value):
            scheme, host = m.group(1).lower(), m.group(2).lower()
            if host and scheme not in WEB and host not in names and host not in ("localhost", "127.0.0.1"):
                refuse(f"your settings point at {host}")
        if "://" not in value and re.search(r"(HOST|HOSTNAME|SERVER)$", name) and STORE_NAME.search(name):
            host = value.split(":")[0].lower()
            if re.fullmatch(r"[a-z0-9.\-]+", host) and host not in names and host not in ("localhost", "127.0.0.1"):
                refuse(f"your settings point at {host}")


def check_services(services):
    for key, svc in services.items():
        if key not in SCAFFOLD_SERVICES:
            refuse(f"it has a service make-it's set-up doesn't have: {key}")
    for key, svc in services.items():
        for opt in SERVICE_OPTIONS:
            if svc.get(opt):
                refuse(f"its {key} service sets {opt}")


def check_networks(cfg, services, project):
    nets = cfg.get("networks") or {}
    for key, net in nets.items():
        if (net or {}).get("external") or (net or {}).get("name") != f"{project}_{key}":
            refuse("it uses an outside network")
    if len(nets) != 1 or any(set(svc.get("networks") or {}) - set(nets) or len(svc.get("networks") or {}) > 1
                             for svc in services.values()):
        refuse("it uses more than one network")


def check_storage(cfg, services, project):
    vols = cfg.get("volumes") or {}
    for key, vol in vols.items():
        if (vol or {}).get("external") or (vol or {}).get("name") != f"{project}_{key}":
            refuse("it keeps data in a volume that is not the app's own")
    for key, svc in services.items():
        for m in svc.get("volumes") or []:
            kind = m.get("type")
            if kind == "tmpfs" or (kind == "volume" and m.get("source") in vols):
                continue
            if kind == "bind" and m.get("target") in SCAFFOLD_BINDS:
                continue
            refuse(f"a folder of this computer is mounted into its {key} service" if kind == "bind"
                   else "it keeps data in a volume that is not the app's own")


def hosts_of(value):
    """[(host, port)] when the whole value is read for certain, else None."""
    m = STRICT_URL.fullmatch(value)
    if m:
        return [(m.group(1).lower(), m.group(2))]
    if STRICT_HOSTS.fullmatch(value):
        return [(h.split(":")[0].lower(), (h.split(":") + [None])[1]) for h in value.split(",")]
    return None


def check_addresses(services):
    own = {k.lower() for k in services}
    published = {str(p.get("published")) for svc in services.values() for p in (svc.get("ports") or []) if p.get("published")}
    for name, value in settings_of(services):
        if not value:
            continue
        if ADDRESS_NAME.search(name) or "://" in value:
            if name not in KNOWN_ADDRESSES:
                refuse(f"it has an address setting make-it's set-up doesn't have: {name}")
            hosts = hosts_of(value)
            if hosts is None:
                refuse(f"the address in {name} can't be read for certain")
            for host, port in hosts:
                if host in own or (host in ("localhost", "127.0.0.1") and port and port in published):
                    continue
                refuse(f"{name} points at {host}, outside the app")
    for name, value in settings_of(services):
        if value and CLOUD_NAME.search(name):
            refuse(f"it names cloud storage or an outside service by its keys: {name}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("local", "copy") or (mode == "copy" and len(sys.argv) != 3):
        refuse("its settings can't be checked")
    try:
        cfg = json.load(sys.stdin)
        services = cfg["services"]
        settings_of(services)
        if not isinstance(services, dict) or not services:
            raise ValueError
    except Exception:
        refuse("your app's settings can't be read" if mode == "local" else "its settings can't be read")
    if mode == "local":
        check_local(services)
    else:
        project = sys.argv[2]
        try:
            check_services(services)
            check_networks(cfg, services, project)
            check_storage(cfg, services, project)
            check_addresses(services)
        except SystemExit:
            raise
        except Exception:
            refuse("its settings can't be read")
    sys.exit(0)


if __name__ == "__main__":
    main()
