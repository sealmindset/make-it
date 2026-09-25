---
name: guardrails
description: make-it quality and security guardrails for anything Claude builds in Claude Desktop or Cowork. Use whenever the user asks to build, create, generate, write, scaffold, or change an app, website, web page, dashboard, script, tool, bot, automation, extension, CLI, library, API, artifact, or any other code, so the result follows the make-it tiered guardrails, build standards, and security checks, with anything the sandbox cannot verify listed as deferred. Not for plain questions or explanations that produce no code. In Claude Code, use /make-it instead.
---

# make-it guardrails (Claude Desktop / Cowork)

**Running in Claude Code?** If you have a real shell with Docker and git on the user's machine,
stop here and tell the user to use `/make-it` (new project) or `/resume-it` (existing project)
instead. This skill is the reduced, sandbox-only version.

The rules live in the reference files next to this skill. This file only says how to apply them
where there is no Docker, no running app, and no access to the user's git. Paths that start with
`claude-code:` inside the references exist only in a Claude Code install. They are not available
here, and needing them is the reason a handoff to Claude Code exists.

## Where the work goes

Check what you can do; do not assume:
- **You can write to a folder the user picked (Cowork):** put the project there. Files persist.
- **Otherwise (Desktop chat sandbox):** build in the sandbox and give the user the result as
  downloadable files (a zip for anything with more than a few files) or an artifact.

**Keep it proportional.** For a snippet or a single-file edit, apply the relevant rules
inline and skip the project files (README, CHANGELOG, TODO, the `CLAUDE.md` canary, the name
question). The steps below are for new projects.

## Steps

1. **Classify** the project type with the table in `references/guardrails.md` (Project Type
   Classification). Don't show the user the classification. **Route:** if it is a `web-app` with
   a backend, login, or database, or anything else that needs containers, don't build Tier 1 by
   hand in the sandbox. Finish the plan (the `make-it` skill does this), then offer the `handoff`
   skill. A static page or artifact with no backend is built here.
2. **Apply the rules**: Tier 0 always, plus the matching tier, plus every AI rule marked `AI*` in
   the Tier Activation Matrix when the code calls an AI model. Tier 0 includes the
   **instruction-drift canary**: every generated project gets a root `CLAUDE.md` whose first
   section is the canary. Use the builder's name if you know it (ask once if you don't). If they
   decline, use the fixed token from `references/guardrails.md`.
3. **Pick the expert persona** with `references/expert-personas.md` and work in character, silently.
4. **Verify what the sandbox can run**, for the active tiers:
   - the static checks in `references/build-standards.md`: files, config, secrets, validation,
     code quality, lint/format/type-check if the tools are available
   - the tests the sandbox can execute, and running a CLI, script, or library directly
   - `references/build-verify-security.md` Phase 1 (code pattern scan always; semgrep, bandit,
     and dependency audits only if the tool is present and network access allows) and the
     Phase 2a AI wiring checks
5. **Fix** AUTO-class findings per `references/fix-strategies.md`, then re-run the check that
   found them. For SEMI-AUTO, show the change in plain language before applying it. List MANUAL
   findings for the user.
6. **Record deferred checks.** A check that needs Docker, a running app or its live endpoints,
   the user's git/GitHub (commits, hooks, CI), or deployment gets listed as **DEFERRED** with
   one line saying why. Never mark such a check as passed or imply it ran. This covers all of
   `build-standards.md` Live Verification Checks, `build-verify-security.md` Phase 2b and Phase 3
   rebuilds, and every Tier 1 container, auth-flow, and health-check item.

**Re-verify on every code change** (`references/guardrails.md` Quality section, item 18a):
after a fix, re-run whatever checks from step 4 can actually run here on the changed area;
any check that still can't run here reverts to DEFERRED in the handoff, never a stale pass.

Tell the user, in plain words, what was checked, what was fixed, and what is deferred. If
anything is deferred and the user wants it fully verified, offer the `handoff` skill. It
packages the project so Claude Code can finish those checks.
