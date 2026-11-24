"""Run one threats-it script, unchanged, against the stand-in (server.py) instead of the real services.

  PATH="scripts/threats-it-stand-in:$PATH" python3 -I scripts/threats-it-stand-in/run.py <port> <script.py> [its arguments]

Every request the script makes, through urlopen or any opener it builds, is sent to 127.0.0.1:<port>; a request to
anything else (a host that is not faked, another local port) is refused, so a script under test can never reach a real
tenant or hand a key to another listener. The client's wait is capped at 1 second so a timeout is quick to test.
"""
import runpy
import sys
import urllib.request

HOSTS = {"https://graph.microsoft.com": "/graph", "https://management.azure.com": "/arm",
         "https://api.loganalytics.io": "/la", "https://attack.mitre.org": "/attack"}
port, script = sys.argv[1], sys.argv[2]
here = f"http://127.0.0.1:{port}/"
real_open = urllib.request.OpenerDirector.open


def open_(self, req, data=None, timeout=None):
    url = req if isinstance(req, str) else req.full_url
    for host, prefix in HOSTS.items():
        if url.startswith(host + "/"):
            url = f"http://127.0.0.1:{port}{prefix}{url[len(host):]}"
            break
    else:
        if not url.startswith(here):
            raise SystemExit("stand-in: refused a request to something that is not the stand-in: " + url.split("/")[2])
    if isinstance(req, str):
        req = url
    else:
        req.full_url = url
    return real_open(self, req, data, timeout=1)


urllib.request.OpenerDirector.open = open_   # every opener: urlopen's own and any a script builds
sys.argv = sys.argv[2:]
runpy.run_path(script, run_name="__main__")
