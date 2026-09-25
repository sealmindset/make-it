---
name: debug-it
description: Root-cause-first debugging in Claude Desktop or Cowork for any bug, error, failing test, build failure, or unexpected behavior in code the user shares. Finds the real cause before proposing a fix, looks for both "something is missing" and "we're doing too much" causes, and stops looping after repeated failed fixes. Reproduces and verifies only what the sandbox can actually run; anything that needs the live app, Docker, a database, or the user's machine is marked deferred. In Claude Code, use /debug-it instead.
---

# debug-it (Claude Desktop / Cowork)

**Running in Claude Code?** If you have a real shell with Docker and git on the user's machine,
stop here and tell the user to run `/debug-it` instead.

The method is `references/debug-it.md`. Follow all of it: the two laws, the hard rules, the four
phases, the circuit-breaker, and the decision card. The overrides below only cover what the
sandbox cannot do. Where the two disagree, this file wins. Paths in the references that start
with `claude-code:` exist only in a Claude Code install. They are not available here.

## What you can run here

Check what you can do; do not assume:
- **You can write to a folder the user picked (Cowork):** read the project there and make the
  fix there. Files persist.
- **Otherwise (Desktop chat sandbox):** work on what the user uploaded or pasted, and hand back
  the changed files (a zip for more than a few) or a diff.

You can run the user's code in the sandbox when it runs on its own: a script, a CLI, a library,
unit tests, a self-contained page. You cannot reach their running app, their Docker containers,
their database, their network services, or anything else on their machine.

## Overrides

| debug-it.md | In Desktop |
|---|---|
| Hard rule 2, Phase 1 "Reproduce & isolate" | Reproduce only in the sandbox, with the user's own code, logs, and errors. If the bug needs the live app, Docker, their database, or their machine, do not fake a reproduction. Gather evidence instead: ask for the full error, logs, a screenshot or screen recording, browser console output, or a network export. Then mark **Reproduction: DEFERRED** with the reason. |
| Hard rule 3, "Check recent changes" | If the project folder includes its git history and git works here, use it. Otherwise ask the user what changed recently (code, packages, settings, the service it talks to). If they can, ask them to paste the output of `git log -5` and `git diff`. |
| Phase 1, UI bugs "drive it (Playwright / a capture tool)" | Drive it only if the page is self-contained and a browser tool is present in the sandbox. Otherwise ask the user for a capture (screenshot, recording, console, network export). |
| Phase 1, "instrument each boundary" | If the code runs here, add the logging here. If it doesn't, give the user the exact log lines to add and where, ask them to run it once, and paste back the output. |
| Hard rule 10, "Fan out" (`/dispatch-it`, parallel agents) | Not available here. Take independent failures one at a time, each through the full method, and say that is what you are doing. |
| Phase 4, "Implement" | After the user picks from the decision card, make the change in the Cowork folder or in the copy you hand back. |
| Phase 4, "Verify" | Say "verified" only if the failing test or reproduction ran again here and passed. If it could not run here, deliver the fix and the failing test anyway and mark **Verification: DEFERRED** with the reason. Never call a fix verified, done, or working unless it ran here. |
| Phase 4, "Capture the lesson" | Write it into the project's notes if you can write to their folder. Otherwise put it in your reply. |
| The note about a project shipping its own `/debug-it` | Does not apply here. |

## Reporting

When you finish, add two lines under the decision card or the fix summary:

```
Reproduced here: yes | DEFERRED -- <why>
Verified here:   yes | DEFERRED -- <why>
```

If anything is deferred and the user wants it reproduced or verified on the real system, offer
the `handoff` skill. It packages the project and the deferred checks so Claude Code can finish.
