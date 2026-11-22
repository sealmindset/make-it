#!/usr/bin/env python3
"""Add (or remove) make-it's no-force-push hook in a Claude Code settings.json, keeping everything else.

Usage: add-no-force-push-hook.py <settings.json> <hook command> <hook file> <state file> [auto|add|remove]
  auto    add it, unless the user removed it: a state file saying "removed", or one saying "added"
          while settings.json no longer has it (the user took it out), keeps it off
  add     add it, whatever the state file says (the installers' "add it back" flag)
  remove  take it out, and record "removed" so later installs leave it out
Prints one line for the installer to show. Exit 0 = done (or nothing to do); 1 = the settings file
can't be read as a JSON object this can merge into, or can't be written: nothing changed.

The entry counts as installed only when it is exactly the one this install writes (same command,
onFailure "block") and the hook file exists; an older make-it entry (another path, another form) is
replaced, never duplicated. Before the first change to an existing file, a copy is kept beside it as
settings.json.bak-<time>. A settings file that is a link stays a link. install.ps1 does the same with
add-no-force-push-hook.ps1; scripts/test-no-force-push.sh runs both on the same fixtures.
"""
import json
import os
import shutil
import sys
import tempfile
import time

MARK = "make-it/hooks/no-force-push.sh"


class Unusable(Exception):
    pass


def no_constants(name):
    raise ValueError("%s is not JSON" % name)


def read_settings(real):
    if not os.path.exists(real):
        return False, {}
    try:
        with open(real, "rb") as f:
            raw = f.read()
        text = raw.decode("utf-8-sig")  # a UTF-8 byte-order mark is read past; a bad byte stops here
        data = json.loads(text, parse_constant=no_constants) if text.strip() else {}
    except (UnicodeDecodeError, ValueError) as e:
        raise Unusable("is not valid JSON (%s)" % e)
    except OSError as e:
        raise Unusable("can't be read (%s)" % e.strerror)
    if not isinstance(data, dict):
        raise Unusable("does not hold a JSON object")
    hooks = data.get("hooks", {})
    if not isinstance(hooks, dict):
        raise Unusable('has a "hooks" entry that is not an object')
    if not isinstance(hooks.get("PreToolUse", []), list):
        raise Unusable('has a "hooks.PreToolUse" entry that is not a list')
    return True, data


def ours_in(entry):
    hs = entry.get("hooks") if isinstance(entry, dict) else None
    return [h for h in hs if isinstance(h, dict) and MARK in str(h.get("command", ""))] if isinstance(hs, list) else []


def without_ours(pre):
    out = []
    for entry in pre:
        mine = ours_in(entry)
        if not mine:
            out.append(entry)
            continue
        rest = [h for h in entry["hooks"] if h not in mine]
        if rest:
            out.append(dict(entry, hooks=rest))
    return out


def write(path, real, existed, data):
    d = os.path.dirname(real) or "."
    if existed and not os.access(real, os.W_OK):
        raise Unusable("is read-only")
    if not os.access(d if os.path.isdir(d) else os.path.dirname(d) or ".", os.W_OK):
        raise Unusable("is in a folder I can't write to")
    backup = None
    try:
        text = json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
        os.makedirs(d, exist_ok=True)
        if existed:
            backup = "%s.bak-%s" % (real, time.strftime("%Y%m%d-%H%M%S"))
            n = 1
            while os.path.exists(backup):
                n += 1
                backup = "%s.bak-%s-%d" % (real, time.strftime("%Y%m%d-%H%M%S"), n)
            shutil.copy2(real, backup)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".settings.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text)
            if existed:
                shutil.copymode(real, tmp)
            os.replace(tmp, real)
        except BaseException:
            os.unlink(tmp)
            raise
    except (OSError, ValueError) as e:
        raise Unusable("couldn't be written (%s)" % (getattr(e, "strerror", None) or e))
    return backup


def set_state(state_file, value):
    try:
        os.makedirs(os.path.dirname(state_file) or ".", exist_ok=True)
        with open(state_file, "w", encoding="utf-8") as f:
            f.write(value + "\n")
    except OSError:
        pass  # the settings change stands; the next install reads settings.json again


def main(path, command, hook_file, state_file, mode):
    real = os.path.realpath(path)
    try:
        existed, data = read_settings(real)
    except Unusable as e:
        return fail(path, str(e))
    try:
        with open(state_file, encoding="utf-8") as f:
            state = f.read().strip()
    except OSError:
        state = ""
    hooks = data.setdefault("hooks", {}) if existed or mode != "remove" else {}
    pre = hooks.get("PreToolUse", []) if isinstance(hooks, dict) else []
    present = [h for e in pre for h in ours_in(e)]
    want = {"type": "command", "command": command, "onFailure": "block"}
    try:
        if mode == "remove":
            set_state(state_file, "removed")
            if not present:
                print("The guard that stops git push --force isn't in %s; it stays off." % path)
                return 0
            hooks["PreToolUse"] = without_ours(pre)
            if not hooks["PreToolUse"]:
                del hooks["PreToolUse"]
            if not hooks:
                del data["hooks"]
            b = write(path, real, existed, data)
            print("Removed the guard that stops git push --force from %s (your old file is kept as %s). "
                  "Later installs leave it out." % (path, os.path.basename(b)))
            return 0
        if mode == "auto" and (state == "removed" or (state == "added" and not present)):
            set_state(state_file, "removed")
            print("The guard that stops git push --force stays off, as you chose.")
            return 0
        if present == [want] and os.path.isfile(hook_file):
            set_state(state_file, "added")
            print("The guard that stops git push --force is already in %s." % path)
            return 0
        hooks["PreToolUse"] = without_ours(pre) + [{"matcher": "Bash", "hooks": [want]}]
        b = write(path, real, existed, data)
        set_state(state_file, "added")
        print("%s the guard that stops git push --force in %s%s." % (
            "Updated" if present else "Added", path,
            " (your old file is kept as %s)" % os.path.basename(b) if b else ""))
        return 0
    except Unusable as e:
        return fail(path, str(e))


def fail(path, why):
    sys.stderr.write("Your Claude settings file %s %s, so I didn't change it. The guard that stops "
                     "git push --force is not changed. Fix or move that file, then run the installer "
                     "again.\n" % (path, why))
    return 1


if __name__ == "__main__":
    if len(sys.argv) not in (5, 6) or (len(sys.argv) == 6 and sys.argv[5] not in ("auto", "add", "remove")):
        sys.stderr.write(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) == 6 else "auto"))
