#!/usr/bin/env python3
"""Add make-it's no-force-push hook to a Claude Code settings.json, keeping everything else in it.

Usage: add-no-force-push-hook.py <settings.json> <hook command>
  exit 0  added, or already there (then nothing is written and nothing is backed up)
  exit 1  the file can't be read as a JSON object this can merge into: nothing written

Before the first change to an existing file, a copy is kept beside it as settings.json.bak-<time>.
A settings file that is a link stays a link: the file it points to is the one changed.
install.ps1 does the same with add-no-force-push-hook.ps1; scripts/test-no-force-push.sh tests both.
"""
import json
import os
import shutil
import sys
import tempfile
import time

MARK = "make-it/hooks/no-force-push.sh"


def main(path, command):
    real = os.path.realpath(path)
    exists = os.path.exists(real)
    text = ""
    try:
        if exists:
            with open(real, encoding="utf-8") as f:
                text = f.read()
        data = json.loads(text) if text.strip() else {}
    except ValueError as e:
        return fail(path, "is not valid JSON (%s)" % e)
    if not isinstance(data, dict):
        return fail(path, "does not hold a JSON object")
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        return fail(path, 'has a "hooks" entry that is not an object')
    pre = hooks.get("PreToolUse", [])
    if not isinstance(pre, list):
        return fail(path, 'has a "hooks.PreToolUse" entry that is not a list')
    for entry in pre:
        for h in (entry.get("hooks") or []) if isinstance(entry, dict) else []:
            if isinstance(h, dict) and MARK in str(h.get("command", "")):
                print("The guard that refuses git push --force is already in %s." % path)
                return 0
    pre.append({"matcher": "Bash", "hooks": [{"type": "command", "command": command}]})
    hooks["PreToolUse"] = pre
    data["hooks"] = hooks
    if exists:
        backup = "%s.bak-%s" % (real, time.strftime("%Y%m%d-%H%M%S"))
        n = 1
        while os.path.exists(backup):
            n += 1
            backup = "%s.bak-%s-%d" % (real, time.strftime("%Y%m%d-%H%M%S"), n)
        shutil.copy2(real, backup)
    d = os.path.dirname(real) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        if exists:
            shutil.copymode(real, tmp)
        os.replace(tmp, real)
    except BaseException:
        os.unlink(tmp)
        raise
    print("Added a guard to %s that stops Claude from running git push --force%s." %
          (path, " (your old file is kept as %s)" % os.path.basename(backup) if exists else ""))
    return 0


def fail(path, why):
    sys.stderr.write("Your Claude settings file %s %s, so I didn't change it. The guard that stops "
                     "git push --force is not added. Fix or move that file, then run the installer "
                     "again.\n" % (path, why))
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
