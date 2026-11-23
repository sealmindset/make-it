#!/usr/bin/env python3
"""render-managed-settings.py -- check a Claude Code managed-settings JSON file and render it for delivery.

Usage:  render-managed-settings.py SETTINGS.json --out DIR [--allow-content-flags]

Checks, before anything is written:
  - the file is well-formed JSON whose top level is an object, with no key given twice and no null value
    (a macOS plist can't hold one);
  - no placeholder such as <collector-host> or <ingest-token> is left unfilled;
  - no content flag is switched on (OTEL_LOG_USER_PROMPTS, OTEL_LOG_ASSISTANT_RESPONSES, OTEL_LOG_TOOL_DETAILS,
    OTEL_LOG_TOOL_CONTENT other than "0" or unset; OTEL_LOG_RAW_API_BODIES set at all), unless
    --allow-content-flags says the organization has decided to collect that content.
Then writes, into DIR (created if missing, files readable by their owner only, because they hold the token):
  com.anthropic.claudecode.plist  the payload for the com.anthropic.claudecode managed preferences domain
  ClaudeCode-Settings.reg         the JSON as the Settings value under HKLM\\SOFTWARE\\Policies\\ClaudeCode

A refusal names the key (for example env.OTEL_EXPORTER_OTLP_ENDPOINT) and never prints a value: the file holds
the collector token. It reads one file and writes two; it changes no setting on this computer and sends nothing.
Exit 0 = rendered, 1 = refused, 2 = could not run (usage, unreadable file, unwritable folder).
Python 3.9+, standard library only.
"""
import argparse
import json
import os
import plistlib
import re
import sys

CONTENT_FLAGS = ("OTEL_LOG_USER_PROMPTS", "OTEL_LOG_ASSISTANT_RESPONSES", "OTEL_LOG_TOOL_DETAILS",
                 "OTEL_LOG_TOOL_CONTENT")
RAW_BODIES = "OTEL_LOG_RAW_API_BODIES"
PLACEHOLDER = re.compile(r"<[A-Za-z][A-Za-z0-9_.-]*>")
PLIST_NAME = "com.anthropic.claudecode.plist"
REG_NAME = "ClaudeCode-Settings.reg"


class Refused(Exception):
    pass


def no_duplicates(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise Refused(f"the key {k!r} is given twice")
        seen[k] = v
    return seen


def walk(node, path, problems):
    """Every placeholder and null, by key path. Keys are checked too; values are never reported."""
    if isinstance(node, dict):
        for k, v in node.items():
            p = f"{path}.{k}" if path else k
            if PLACEHOLDER.search(k):
                problems.append(f"{p}: the key name holds an unfilled placeholder")
            walk(v, p, problems)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}[{i}]", problems)
    elif node is None:
        problems.append(f"{path}: null (a plist can't hold it; leave the key out instead)")
    elif isinstance(node, str) and PLACEHOLDER.search(node):
        problems.append(f"{path}: an unfilled placeholder")


def content_flags_on(settings):
    env = settings.get("env")
    if not isinstance(env, dict):
        return []
    on = [f"env.{k}" for k in CONTENT_FLAGS if k in env and env[k] not in ("0", "")]
    if RAW_BODIES in env and env[RAW_BODIES] != "":
        on.append(f"env.{RAW_BODIES}")
    return on


def check(raw, allow_content):
    try:
        settings = json.loads(raw, object_pairs_hook=no_duplicates)
    except json.JSONDecodeError as e:  # the message is the position only, never the text
        raise Refused(f"not valid JSON (line {e.lineno}, column {e.colno})")
    if not isinstance(settings, dict):
        raise Refused("the top level is not a JSON object")
    problems = []
    walk(settings, "", problems)
    env = settings.get("env")
    if env is not None and not isinstance(env, dict):
        problems.append("env: not an object")
    elif isinstance(env, dict):
        problems += [f"env.{k}: not a string (env values are strings)" for k, v in env.items()
                     if v is not None and not isinstance(v, str)]
    flags = content_flags_on(settings)
    if flags and not allow_content:
        problems += [f"{k}: a content flag is switched on (pass --allow-content-flags only if your organization "
                     f"has decided to collect that content and told its people)" for k in flags]
    if problems:
        raise Refused("\n  ".join(["refused:"] + problems))
    return settings, flags


def reg_text(settings):
    value = json.dumps(settings, ensure_ascii=True, separators=(",", ":"))
    value = value.replace("\\", "\\\\").replace('"', '\\"')
    return ("Windows Registry Editor Version 5.00\r\n\r\n"
            "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\ClaudeCode]\r\n"
            f'"Settings"="{value}"\r\n')


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)


def main(argv):
    ap = argparse.ArgumentParser(description="Check a managed-settings JSON file and render the plist and "
                                             "registry forms.")
    ap.add_argument("settings", help="the managed-settings JSON file")
    ap.add_argument("--out", required=True, help="folder to write the two rendered files into")
    ap.add_argument("--allow-content-flags", action="store_true",
                    help="render even though a content flag is switched on")
    a = ap.parse_args(argv)
    try:
        with open(a.settings, "rb") as f:
            raw = f.read().decode("utf-8-sig")
    except (OSError, UnicodeDecodeError) as e:
        print(f"could not read {a.settings}: {type(e).__name__}", file=sys.stderr)
        return 2
    try:
        settings, flags = check(raw, a.allow_content_flags)
        plist = plistlib.dumps(settings, fmt=plistlib.FMT_XML, sort_keys=False)
        if plistlib.loads(plist) != settings:  # ponytail: read-back self-check; plutil -lint is the test's job
            raise Refused("the plist did not read back to the same settings")
    except Refused as e:
        print(f"{a.settings}: {e}", file=sys.stderr)
        return 1
    except (OverflowError, TypeError, ValueError):
        print(f"{a.settings}: refused: a value can't be written to a plist", file=sys.stderr)
        return 1
    try:
        os.makedirs(a.out, exist_ok=True)
        write_private(os.path.join(a.out, PLIST_NAME), plist)
        write_private(os.path.join(a.out, REG_NAME), reg_text(settings).encode("utf-16"))
    except OSError as e:
        print(f"could not write to {a.out}: {type(e).__name__}", file=sys.stderr)
        return 2
    for k in flags:
        print(f"note: {k} is switched on, so that content will be collected (--allow-content-flags)",
              file=sys.stderr)
    print(f"checked {a.settings}; wrote {PLIST_NAME} and {REG_NAME} to {a.out} (they hold the token: "
          f"keep them private)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
