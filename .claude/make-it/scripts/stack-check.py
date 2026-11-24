#!/usr/bin/env python3
"""Where would this app's stack reach and keep its data? Two callers.

Reads `docker compose --profile dev config --format json` on stdin (settings already resolved: the Compose file,
`.env`, env files).

  stack-check.py local
      /resume-it's live pass ("settings point at this machine", deadcode.md section 5's "Settings first" bullet):
      a database, queue or cache address must be a Compose service, localhost or 127.0.0.1.
  stack-check.py ai-settings
      Prints the AI provider's address and key settings, one NAME a line. The write test starts its copy with
      every one of them emptied, so the copy can never call a paid or outside AI service.
  stack-check.py copy PROJECT
      /make-it's write test, before it starts the temporary copy named PROJECT. The copy is used only on a set-up
      make-it's build produces: an allow-list, never a list of unsafe shapes. Every one of these must hold, or the
      set-up is "not one make-it's build produces" and the write test is not run:
        - only Compose's name, services, networks and volumes;
        - every service is one the scaffolds define, or a mock service the build generates (named mock-<name>,
          in the dev profile, built from ./mock-services/mock-<name>), and uses only the options those use;
        - one network, the project's own (a plain bridge, not external, no fixed name);
        - every volume is the project's own plain named volume; no folder of this computer is mounted;
        - every AI-provider setting is empty in the copy;
        - an address setting the scaffolds know is read for certain and points at one of the copy's own services
          or the copy's own published port on this machine;
        - any other setting whose name or value looks like an address is read for certain and points at one of
          the copy's generated mock services (or the copy's own published port); plain values are fine;
        - no cloud storage or outside service is named by its keys.

Exit 0 and print nothing: it may start. Exit 1 and print the first reason in plain words: it must not. Anything
unknown or unreadable is a refusal. It never prints a setting's value: a host name or a setting's NAME at most (a
URL can hold a password), and for an address it can't read for certain, the NAME only.

The sets below are what the two scaffolds' own files define; scripts/test-live-checks-write-copy.sh derives them
from those files and fails when they differ.
"""
import json
import re
import sys

# --- what make-it's build produces (fastapi-nextjs and nextjs-fullstack) ---
TOP_KEYS = {"name", "services", "networks", "volumes"}
SCAFFOLD_SERVICES = {"frontend", "backend", "app", "db", "mock-oidc"}
SERVICE_KEYS = {"build", "depends_on", "environment", "healthcheck", "image", "networks", "ports", "profiles",
                "volumes"}
BUILD_KEYS = {"context", "dockerfile", "args"}
SCAFFOLD_BINDS = set()                      # container paths the scaffolds mount a folder of this computer on: none
KNOWN_ADDRESSES = {"DATABASE_URL", "OIDC_ISSUER_URL", "OIDC_EXTERNAL_URL", "FRONTEND_URL", "BACKEND_URL",
                   "BACKEND_INTERNAL_URL", "NEXTAUTH_URL", "MOCK_OIDC_EXTERNAL_BASE_URL",
                   "MOCK_OIDC_INTERNAL_BASE_URL", "CRIBL_STREAM_URL", "TRUSTED_PROXIES"}
# the scaffolds' other settings: their values are the app's own business (a secret may hold any character)
SCAFFOLD_PLAIN = {"POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET",
                  "JWT_SECRET", "ENFORCE_SECRETS", "LOG_BUFFER_SIZE", "MOCK_OIDC_PORT", "MOCK_OIDC_CLIENT_ID",
                  "MOCK_OIDC_CLIENT_SECRET", "DOCKER_HUB_PREFIX", "MCR_PREFIX", "GHCR_PREFIX", "DB_PORT",
                  "CRIBL_STREAM_TOKEN"}
# the AI provider's address and key settings (the scaffold's config.py, and the two the provider SDKs read)
AI_SETTINGS = ("AZURE_AI_FOUNDRY_ENDPOINT", "AZURE_AI_FOUNDRY_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL",
               "OPENAI_API_KEY", "OPENAI_BASE_URL", "OLLAMA_BASE_URL", "CLAUDE_CODE_OAUTH_TOKEN")
ADDRESS_NAME = re.compile(r"(URL|URI|DSN|ENDPOINT|HOST|HOSTNAME|SERVER|SERVERS|BROKER|BROKERS|ADDR|ADDRESS|PROXIES"
                          r"|CONNECTION|CONNECTION_STRING)$")
CLOUD_NAME = re.compile(r"^(AWS_|S3_|GCS_|GCP_|GOOGLE_CLOUD_|GOOGLE_APPLICATION_CREDENTIALS|AZURE_STORAGE|R2_|MINIO_"
                        r"|SUPABASE_|FIREBASE_|CLOUDINARY_)|BUCKET|BLOB|SAS_TOKEN")
# an address read for certain: scheme://[user[:password]@]host[:port][/path], plain characters only; or host[,host...]
STRICT_URL = re.compile(r"[a-z][a-z0-9+.\-]*://(?:[A-Za-z0-9._~%\-]+(?::[A-Za-z0-9._~%\-]*)?@)?([A-Za-z0-9.\-]+)"
                        r"(?::(\d+))?(?:[/?#][^\s@\\]*)?")
STRICT_HOSTS = re.compile(r"[A-Za-z0-9.\-]+(?::\d+)?(?:,[A-Za-z0-9.\-]+(?::\d+)?)*")
# a value that names another machine: a URL, an @, an IP address, name:port, or a dotted name ending in letters
HOST_LIKE = re.compile(r"://|@|\b\d{1,3}(?:\.\d{1,3}){3}\b|\b[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*:\d+\b"
                       r"|\b[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}\b")

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


def generated_mock(key, svc):
    """A mock service as the build generates one: mock-<name>, dev profile only, built from ./mock-services/<key>."""
    context = str(((svc.get("build") or {}).get("context")) or "").replace("\\", "/").rstrip("/").split("/")
    return (bool(re.fullmatch(r"mock-[a-z0-9][a-z0-9\-]*", key)) and svc.get("profiles") == ["dev"]
            and context[-2:] == ["mock-services", key])


def check_services(cfg, services):
    extra = sorted(k for k, v in cfg.items() if v and k not in TOP_KEYS)
    if extra:
        refuse(f"it uses a part of Compose make-it's build doesn't use: {extra[0]}")
    for key, svc in services.items():
        if key not in SCAFFOLD_SERVICES and not generated_mock(key, svc):
            refuse(f"it has a service make-it's build doesn't produce: {key}")
    for key, svc in services.items():
        for opt in sorted(k for k, v in svc.items() if v and k not in SERVICE_KEYS):
            refuse(f"its {key} service sets {opt}")
        for opt in sorted(k for k, v in (svc.get("build") or {}).items() if v and k not in BUILD_KEYS):
            refuse(f"its {key} service's build sets {opt}")


def check_networks(cfg, services, project):
    nets = cfg.get("networks") or {}
    for key, net in nets.items():
        net = net or {}
        if (net.get("external") or net.get("name") != f"{project}_{key}" or net.get("driver") not in (None, "bridge")
                or any(v for k, v in net.items() if k not in ("name", "driver"))):
            refuse("it uses an outside network")
    if len(nets) != 1 or any(set(svc.get("networks") or {}) - set(nets) or len(svc.get("networks") or {}) > 1
                             or any((svc.get("networks") or {}).values()) for svc in services.values()):
        refuse("it uses more than one network")


def check_storage(cfg, services, project):
    vols = cfg.get("volumes") or {}
    for key, vol in vols.items():
        vol = vol or {}
        if vol.get("external") or vol.get("name") != f"{project}_{key}" or any(v for k, v in vol.items() if k != "name"):
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
    mocks = {k.lower() for k, svc in services.items() if k not in SCAFFOLD_SERVICES and generated_mock(k, svc)}
    published = {str(p.get("published")) for svc in services.values() for p in (svc.get("ports") or []) if p.get("published")}
    settings = settings_of(services)
    for name, value in settings:
        if value and name in AI_SETTINGS:
            refuse(f"its AI provider setting {name} can't be emptied for the copy")
    for name, value in settings:
        if not value or name in SCAFFOLD_PLAIN:
            continue
        if name in KNOWN_ADDRESSES:
            hosts = hosts_of(value)
            if hosts is None:
                refuse(f"the address in {name} can't be read for certain")
            for host, port in hosts:
                if host in own or (host in ("localhost", "127.0.0.1") and port and port in published):
                    continue
                refuse(f"{name} points at {host}, outside the app")
        elif ADDRESS_NAME.search(name) or HOST_LIKE.search(value):
            # a setting the scaffolds don't define: fine only when it surely points at one of the copy's own mocks
            if value.startswith(("/", "./")) and "://" not in value and "@" not in value:
                continue                         # a path inside the app
            hosts = hosts_of(value)
            if hosts is None or not all(h in mocks or (h in ("localhost", "127.0.0.1") and p and p in published)
                                        for h, p in hosts):
                refuse(f"it has a setting make-it's build doesn't produce that holds an address: {name}")
    for name, value in settings:
        if value and CLOUD_NAME.search(name):
            refuse(f"it names cloud storage or an outside service by its keys: {name}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "ai-settings":
        print("\n".join(AI_SETTINGS))
        sys.exit(0)
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
            check_services(cfg, services)
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
