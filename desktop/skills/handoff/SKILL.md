---
name: handoff
description: Package a project from Claude Desktop or Cowork so the user can continue it in Claude Code on their own computer. Writes a handoff.md (goal, state, files, changes, failed approaches, next steps, and every check that could not run here) and bundles it with the project files and .make-it/app-context.json, never including secrets. Use when the make-it, guardrails, debug-it, or nemo-it skill offers a handoff and the user accepts, or when the user asks to continue, ship, deploy, run, or finish the app in Claude Code. In Claude Code, use /resume-it instead.
---

# handoff (Claude Desktop / Cowork)

**Running in Claude Code?** If you have a real shell with Docker and git on the user's machine,
there is nothing to hand off. Stop here and tell the user to run `/resume-it` instead.

The `handoff.md` format and its rules are `/clear-it`'s, in `references/clear-it.md`. Follow its
`gather`, `archive`, and `write` steps, with the overrides below. Where the two disagree, this
file wins. Paths in the references that start with `claude-code:` exist only in a Claude Code
install. They are not available here.

## Where the bundle goes

Check what you can do; do not assume:
- **You can write to a folder the user picked (Cowork):** write `handoff.md` (and anything else
  below that isn't there yet) into that folder. No zip needed. The folder is the bundle.
- **Otherwise (Desktop chat sandbox):** build the bundle in the sandbox and give the user one
  downloadable zip named `<project-slug>-handoff.zip`. The slug is the project name in lowercase
  with hyphens, for example `recipe-box-handoff.zip`.

## What goes in the bundle

- The project files. Leave out `.git/` and folders that get rebuilt anyway, like
  `node_modules/`, `.venv/`, and build output.
- `.make-it/app-context.json`, if the project has one (see `references/app-context.md`).
- `handoff.md` at the project root.
- The root `CLAUDE.md` with the instruction-drift canary, if the project has one.

**Never include secrets.** Leave out `.env` and every other file holding real keys, tokens,
passwords, or certificates (for example `.env.local`, `.env.production`, `*.pem`, `*.key`,
credentials JSON files). `.env.example` goes in, with placeholder values only. Never copy a
secret value into `handoff.md`. Tell the user plainly that their secrets were left out on
purpose and that Claude Code will set up a fresh `.env` from `.env.example`.

Before bundling, check that `.env.example` holds placeholders only (no real-looking values such
as an `sk-ant-` key or a filled-in `CLAUDE_CODE_OAUTH_TOKEN`), and that no secret value appears
in `handoff.md`, `.handoff-history.md`, or `.make-it-state.md`. If you find one, replace it with
a placeholder and tell the user in plain words what you removed and where (never the value).

## Overrides to clear-it.md

| clear-it.md | In Desktop |
|---|---|
| `gather` step 2 (git commands) | Run them only if the project includes its git history and git works here. Otherwise use the conversation and the files. |
| `gather` step 4 (thin context) | Ask the one question only if there is no plan, no build, and no deferred check to record. |
| `archive` | As written, whenever a `handoff.md` is already in the project. |
| `write`: title block | Put `Source: claude-desktop` on its own line directly under the `# Handoff -- <project name>` title, then the `_Written ..._` line with "by the handoff skill (Claude Desktop)" instead of "by /clear-it". |
| `write`: 4. Changes Made | Nothing was committed here. Mark each change "not committed (made in Claude Desktop)". |
| `write`: 6. Next Steps | Say what Claude Code does after the deferred checks. If nothing is built yet (the `make-it` plan route), write: "1. There is no app code yet: build the app from the finished plan in `.make-it/app-context.json`, without asking the design questions again. First check the computer is ready (make-it `preflight` machine checks), then build it (`build-project`) and check it works (`build-verify`)." The user still just types `/resume-it`. If the user asked to ship or deploy, the last step is `/ship-it` (see `references/ship-it-guide.md` for what it needs). |
| `write`: after section 6 | Add a `## Deferred Checks` section (below). |
| `handoff` step (the reset message) | Does not apply. Use "Tell the user" below. |
| guardrail "NEVER commit, push, ... or modify code" | Still holds. Besides `handoff.md` and `.handoff-history.md`, this skill writes only the zip (Chat) or the bundle files into the user's folder (Cowork), plus placeholder fixes from the secrets check. |

## Deferred Checks

List every check that was marked DEFERRED or NOT RUN in this conversation, one per line:

```
- <what to check> -- not run here: <why> -- in Claude Code: <how to run it>
```

Collect them from wherever they came up:
- **guardrails / make-it build-verify:** every DEFERRED item, including Live Verification Checks,
  build-verify-security Phase 2b and Phase 3 rebuilds, Tier 1 container, login, and health
  checks, git hooks and CI, and every `DEFERRED` line in `.make-it-state.md`.
- **debug-it:** `Reproduction: DEFERRED` and `Verification: DEFERRED`, with the bug, the
  suspected cause, the fix that was made, and the test or steps that prove it.
- **nemo-it:** every item in the attestation's `Not Run (Deferred)` section. Claude Code runs
  them with `/nemo-it <mode>`. If the user wants findings fixed, add `/fix-it` to Next Steps.

If there are none, write "None". If nothing has been built yet, write "None -- nothing built
yet; checks run as part of the build". Never list a check as passed that did not run here.

## Tell the user

In plain words, with no jargon:
1. What is in the bundle, and that their secrets were left out on purpose.
2. Claude Code is Anthropic's app that works on the files on their own computer, so it can
   run, test, and publish the app, which this chat can't do.
3. How to continue:
   - Chat: "Download the zip and unzip it. Open that folder in Claude Code, then type `/resume-it`."
   - Cowork: "Open this same folder in Claude Code, then type `/resume-it`."
4. It will first run the checks that couldn't run here, and tell them honestly which passed.
5. If they don't have Claude Code yet, they can get it at https://claude.ai/download. The
   `/make-it` and `/resume-it` commands come from the make-it skills. Setup steps are at
   https://github.com/sealmindset/make-it.

**If the user declines the handoff:** still write `handoff.md` (it holds the plan and what's left
to do) and give them `handoff.md` and `.make-it/app-context.json` as downloadable files, or leave
them in their Cowork folder. Tell them: "Whenever you want to pick this up, put these files in a
folder, open it in Claude Code, and type `/resume-it`."
