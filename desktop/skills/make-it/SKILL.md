---
name: make-it
description: Guide a first-time builder with no coding knowledge from an app idea to a working result in Claude Desktop or Cowork, through friendly plain-language questions. Use when the user wants to make, build, or create an app, tool, or website and would benefit from being guided step by step. Builds what fits in the sandbox and hands anything that needs Docker, a web-app scaffold, or deployment off to Claude Code. In Claude Code, use /make-it instead.
---

# make-it (Claude Desktop / Cowork)

**Running in Claude Code?** If you have a real shell with Docker and git on the user's machine,
stop here and tell the user to run `/make-it` instead (or `/resume-it` for an existing project).

The full flow is `references/make-it.md`. Follow it, with the overrides below. Where the two
disagree, this file wins. Paths in the references that start with `claude-code:` exist only in
a Claude Code install. They are not available here, and needing them is why the handoff exists.

**Where files go:** if you can write to a folder the user picked (Cowork), put the project
there. Otherwise build in the sandbox and deliver downloadable files (a zip for multi-file
projects).

## Step by step

| make-it.md step | In Desktop |
|---|---|
| `update-interceptor` | Does not apply. Skip it. |
| `preflight` | Ask only the name question from item 1 and capture `builder_name` as written. Do not say the "let me do a quick check to make sure your machine is ready" sentence. Skip items 2-6 (machine checks, GREEN/YELLOW/RED, access requests). Record `builder_name` in `.make-it/app-context.json` at Design. |
| `welcome`, `ideation-deep-dive` | As written. Keep the plain-language persona. |
| `design-decisions` | As written: classify the project, pick the expert persona, apply smart defaults from `references/design-blueprint.md`, and write `.make-it/app-context.json` per `references/app-context.md`. **Choose the route below before the plain-English summary.** On the handoff route, end the summary with the handoff line below instead of "Ready for me to start building? This will take a few minutes." |
| `build-project`, `build-verify` | Depends on the route below. |
| `ship-handoff`, and the automatic `/try-it` at the end of Part D | Do not apply. Nothing is deployed from Desktop. |

## Route (decide before the Design summary)

**Hand off** if the design needs any of: the fastapi-nextjs scaffold (`scaffold: "fastapi-nextjs"`),
Docker or Docker Compose, mock services, a running app for live build-verify, the user's git or
GitHub, or deployment. In practice that means every `web-app` with a backend, login, or database,
and any `api-service` that needs containers. Do not start building it. End the summary with:
"Your plan is ready. The building itself happens in Claude Code on your computer. Want me to
package everything up so you can pick it up there?" If they say yes, use the `handoff` skill to
package the design and `app-context.json`.

**Build here** for everything else. That includes a CLI, script, library, or extension, and any
static page or artifact with no backend, even when it looks like a web app.
- Follow `build-project` for the non-scaffold path. Skip the scaffold copy, `git init`, and
  worktree steps. Still write the Tier 0 files: README, CHANGELOG, TODO, `.gitignore`, and
  `CLAUDE.md` with the instruction-drift canary using `builder_name`.
- For `build-verify`, apply the `guardrails` skill. Do Part A and the parts of Parts B and C
  the sandbox can actually run. List everything else as DEFERRED. Never report it as passed.
  This includes the guardrails **Re-verify on every code change** rule (item 18a): after any
  fix cycle, re-run whatever checks can actually run here; anything that still can't reverts
  to DEFERRED.
- **Part D: do not use the fixed text in make-it.md.** Skip the step 40 message ("built and
  verified", "Everything is working"). Instead, tell the user in plain words what was built,
  what was actually checked here, and what is deferred. Claim only what really ran.
- In `.make-it-state.md` (step 41), fill every line from what actually happened:
  - Current Status: describe the real state. Never write "running with all services healthy"
    unless it ran here.
  - Preflight: `SKIPPED (Desktop)`.
  - Each Build-Verify Results line: `PASSED` only if the check ran here, otherwise `DEFERRED`
    with the reason.
  - Next Steps: the `handoff` skill, not /ship-it.
- If anything is deferred, offer the `handoff` skill so Claude Code can finish verifying.
