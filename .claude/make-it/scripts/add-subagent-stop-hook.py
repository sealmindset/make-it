#!/usr/bin/env python3
"""Add make-it's no-leftover-commands hook to a Claude Code settings.json as a SubagentStop hook,
keeping everything else.

Usage: add-subagent-stop-hook.py <settings.json> <hook file> <python> [<bash>]
  The entry's command, built here: <bash> -c '[ -f "$0" ] || exit 0; exec <python> -I "$0"' <hook file>
  (each path quoted for bash). It runs the hook only while its file is there: removing make-it turns
  the check off. Built here, not by the installer, so install.ps1 never has to pass a double quote
  through Windows PowerShell's command line, which drops it.
Prints one line for the installer to show. Exit 0 = done (or already there); 1 = the settings file
can't be read as a JSON object this can merge into, or can't be written: nothing changed.

One entry, no matcher (every helper). An older make-it entry (another path, another form) is
replaced, never doubled; a second run changes nothing. Reading, the copy kept before the first
change, and the write (a link stays a link) are add-no-force-push-hook.py's, so both installers'
settings edits behave the same. install.sh and install.ps1 both run this file: the hook itself
needs Python, so a machine that can run the hook can run this.
"""
import importlib.util
import os
import shlex
import sys

MARK = "make-it/hooks/no-leftover-commands.py"
WHAT = "the check that stops a helper from finishing with a background command still running"

_spec = importlib.util.spec_from_file_location(
    "settings_merge", os.path.join(os.path.dirname(os.path.abspath(__file__)), "add-no-force-push-hook.py"))
merge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(merge)


def ours(entry):
    hs = entry.get("hooks") if isinstance(entry, dict) else None
    return [h for h in hs if isinstance(h, dict) and MARK in str(h.get("command", ""))] if isinstance(hs, list) else []


def main(path, hook_file, python, bash="bash"):
    command = "%s -c '[ -f \"$0\" ] || exit 0; exec %s -I \"$0\"' %s" % (shlex.quote(bash), python, shlex.quote(hook_file))
    real = os.path.realpath(path)
    try:
        existed, data = merge.read_settings(real)
        hooks = data.setdefault("hooks", {})
        stop = hooks.get("SubagentStop", [])
        if not isinstance(stop, list):
            raise merge.Unusable('has a "hooks.SubagentStop" entry that is not a list')
        want = {"type": "command", "command": command}
        present = [h for e in stop for h in ours(e)]
        if present == [want]:
            print("%s is already in %s." % (WHAT[0].upper() + WHAT[1:], path))
            return 0
        kept = []
        for e in stop:
            mine = ours(e)
            if not mine:
                kept.append(e)
            elif [h for h in e["hooks"] if h not in mine]:
                kept.append(dict(e, hooks=[h for h in e["hooks"] if h not in mine]))
        hooks["SubagentStop"] = kept + [{"hooks": [want]}]
        b = merge.write(path, real, existed, data)
    except merge.Unusable as e:
        sys.stderr.write("Your Claude settings file %s %s, so I didn't change it. %s is not added. Fix or "
                         "move that file, then run the installer again.\n" % (path, e, WHAT[0].upper() + WHAT[1:]))
        return 1
    print("%s %s in %s%s." % ("Updated" if present else "Added", WHAT, path,
                              " (your old file is kept as %s)" % os.path.basename(b) if b else ""))
    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5) or sys.argv[3] not in ("python3", "python"):
        sys.stderr.write(__doc__)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))
