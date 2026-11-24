"""Run one threats-it script, unchanged, against the stand-in (server.py) instead of the real services.

  PATH="scripts/threats-it-stand-in:$PATH" python3 -I scripts/threats-it-stand-in/run.py <port> <script.py> [its arguments]

Every request the script makes is sent to 127.0.0.1:<port>; a request to any host that is not faked is refused, so a
script under test can never reach a real tenant. The client's wait is capped at 1 second so a timeout is quick to test.
"""
import runpy
import sys
import urllib.request

HOSTS = {"https://graph.microsoft.com": "/graph", "https://management.azure.com": "/arm",
         "https://api.loganalytics.io": "/la", "https://attack.mitre.org": "/attack"}
port, script = sys.argv[1], sys.argv[2]
real_urlopen = urllib.request.urlopen


def urlopen(req, *args, timeout=None, **kw):
    url = req if isinstance(req, str) else req.full_url
    for host, prefix in HOSTS.items():
        if url.startswith(host + "/"):
            local = f"http://127.0.0.1:{port}{prefix}{url[len(host):]}"
            break
    else:
        raise SystemExit("stand-in: refused a request to a host that is not faked: " + url.split("/")[2])
    if isinstance(req, str):
        req = local
    else:
        req.full_url = local
    return real_urlopen(req, *args, timeout=1, **kw)


urllib.request.urlopen = urlopen
sys.argv = sys.argv[2:]
runpy.run_path(script, run_name="__main__")
