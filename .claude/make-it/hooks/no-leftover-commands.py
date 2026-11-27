#!/usr/bin/env python3
"""SubagentStop hook: a helper may not give its final report while a background command it started is
still running.

A background command a background helper starts keeps running after the helper finishes; in a
session someone works in there is no time limit, so a finished helper can hold one for days. When a
helper tries to finish, this reads that helper's own transcript (agent_transcript_path) and lists:
  started   a Bash or PowerShell call whose result reads "Command running in background with ID: <id>",
            or a command "moved to the background (ID: <id>)" at its timeout
  finished  a <task-notification> for <id> that carries a <status> (completed, failed, killed), or
            any result of a TaskStop call for <id>
When Claude Code sends background_tasks (the session's tasks still in flight), a command missing from
it has ended too. If any is still running, it refuses once: exit 2, one plain line on stderr, which
Claude Code hands the helper as its next instruction.

A tripwire, never a jail: with stop_hook_active set (the helper was already sent back once) it lets
the helper finish. It also lets it finish, and says nothing, when the transcript is missing,
unreadable, a link, outside <session>/subagents/agent-<agent_id>.jsonl beside the main transcript, or
in a format it doesn't know, and on any error of its own. It never reads another helper's transcript.
"""
import json, os, re, sys

STARTERS = ("Bash", "PowerShell")
STARTED = re.compile(r"^Command running in background with ID: ([\w-]+)")
MOVED = re.compile(r"^Command (?:was|did not complete within its \S+ timeout and was) moved to the background \(ID: ([\w-]+)\)", re.M)
NOTICE = re.compile(r"<task-notification>(.*?)</task-notification>", re.S)
TASK_ID = re.compile(r"<task-id>([\w-]+)</task-id>")
STATUS = re.compile(r"<status>(\w+)</status>")


def own_transcript(data):
    """The helper's own transcript path, or None when it isn't exactly where that helper's would be."""
    aid, path, main = data.get("agent_id"), data.get("agent_transcript_path"), data.get("transcript_path")
    if not all(isinstance(x, str) and x for x in (aid, path, main)) or not re.fullmatch(r"[\w-]+", aid):
        return None
    want = os.path.join(os.path.splitext(main)[0], "subagents", "agent-%s.jsonl" % aid)
    if os.path.normpath(os.path.abspath(path)) != os.path.normpath(os.path.abspath(want)) or os.path.islink(path):
        return None
    return path


def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "".join(x.get("text", "") for x in c if isinstance(x, dict) and isinstance(x.get("text"), str))
    return ""


def still_running(path):
    calls, stops, started, ended = set(), {}, [], set()
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if "<task-notification>" in line:
                for note in NOTICE.findall(line):
                    if STATUS.search(note):  # an interim notice (no status) is not an end
                        ended.update(TASK_ID.findall(note))
            if '"tool_use"' not in line and '"tool_result"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            msg = d.get("message") if isinstance(d, dict) else None
            content = msg.get("content") if isinstance(msg, dict) else None
            for b in content if isinstance(content, list) else ():
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                    if b.get("name") in STARTERS:
                        calls.add(b.get("id"))
                    elif b.get("name") == "TaskStop":
                        stops[b.get("id")] = inp.get("task_id") or inp.get("shell_id")
                elif b.get("type") == "tool_result" and d.get("type") == "user":
                    u = b.get("tool_use_id")
                    if u in stops:
                        ended.add(stops[u])  # stopped, or "not running" / "no task found": not running now
                    elif u in calls:
                        text = text_of(b.get("content"))
                        m = STARTED.match(text) or MOVED.search(text)
                        if m:
                            started.append(m.group(1))
    return [t for t in dict.fromkeys(started) if t not in ended]


def main():
    try:
        data = json.loads(sys.stdin.read())
    except ValueError:
        return 0
    if not isinstance(data, dict) or data.get("stop_hook_active") is True:
        return 0
    path = own_transcript(data)
    if not path:
        return 0
    try:
        left = still_running(path)
    except OSError:
        return 0
    live = data.get("background_tasks")
    if isinstance(live, list):
        ids = {t.get("id") for t in live if isinstance(t, dict)}
        left = [t for t in left if t in ids]
    if not left:
        return 0
    sys.stderr.write("You still have a background command running: %s. Stop each with TaskStop, then give your report.\n"
                     % ", ".join(left))
    return 2


try:
    sys.exit(main())
except Exception:
    sys.exit(0)
