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
| `preflight` | Do greeting item 1 only: capture `builder_name` exactly as written. Skip the machine checks, the GREEN/YELLOW/RED buckets, and access requests (items 2-6). Record `builder_name` in `.make-it/app-context.json` at Design. |
| `welcome`, `ideation-deep-dive` | As written. Keep the plain-language persona. |
| `design-decisions` | As written: classify the project, pick the expert persona, apply smart defaults from `references/design-blueprint.md`, write `.make-it/app-context.json` per `references/app-context.md`, then give the plain-English summary and wait for the go-ahead. Then decide the route below. |
| `build-project`, `build-verify` | Depends on the route below. |
| `ship-handoff`, and the automatic `/try-it` at the end of Part D | Do not apply. Nothing is deployed from Desktop. |

## Route after Design

**Hand off** if the design needs any of: the fastapi-nextjs scaffold (`scaffold: "fastapi-nextjs"`),
Docker or Docker Compose, mock services, a running app for live build-verify, the user's git or
GitHub, or deployment. In practice that means every `web-app` project, and any `api-service`
project that needs containers. Do not start building it. Use the `handoff` skill to package
the design and `app-context.json`. Tell the user plainly: the plan is done, and the building
happens in Claude Code, which picks up exactly where this left off.

**Build here** otherwise (for example: a CLI, script, library, extension, or a single-page tool
or artifact):
- Follow `build-project` for the non-scaffold path. Skip the scaffold copy, `git init`, and
  worktree steps. Still write the Tier 0 files: README, CHANGELOG, TODO, `.gitignore`, and
  `CLAUDE.md` with the instruction-drift canary using `builder_name`.
- For `build-verify`, apply the `guardrails` skill. Do Part A and the parts of Parts B and C
  the sandbox can actually run. List everything else as DEFERRED. Never report it as passed.
- For Part D, give an honest plain-language summary of what was built, checked, and deferred.
  In `.make-it-state.md`, list the deferred checks under Build-Verify Results. If anything is
  deferred, offer the `handoff` skill so Claude Code can finish verifying.
