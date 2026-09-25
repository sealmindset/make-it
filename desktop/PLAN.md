# Plan: make-it-desktop plugin (Claude Desktop / Cowork parity)

Approved by Rob, 2026-09-25. Branch `feat/desktop-plugin`.

## Goal
Anything a user builds in Claude Desktop (Chat or Cowork) follows the same guardrails as
/make-it. Work the sandbox cannot do (Docker, local git, gh, live build-verify) is packaged
as a handoff that `/resume-it` in Claude Code continues.

## Global constraints (binding on every task)
- **One source of rules.** Guardrails, build standards, security and fix references are COPIED
  from `.claude/make-it/references/` by the generator. Never hand-copy or paraphrase them into
  `desktop/`. Desktop-specific instructions (sandbox limits, handoff) live only in the
  `desktop/skills/*/SKILL.md` wrappers.
- **Generated output is never hand-edited.** `desktop/build.sh` writes `dist/make-it-desktop/`
  (gitignored). Output must be deterministic: two runs → byte-identical tree.
- **Plugin format:** `.claude-plugin/plugin.json` (`name: make-it-desktop`, version = repo
  `VERSION`), `skills/<name>/SKILL.md` with `name` + `description` frontmatter, each skill's
  supporting files under its own folder. No `bin/` directory (claude.ai/Cowork refuse it).
  No `allowed-tools`/Claude-Code-only frontmatter. Must pass `claude plugin validate`.
- **Import rewriting:** `@~/.claude/make-it/references/X.md` in copied command bodies becomes a
  relative `references/X.md` link inside the skill folder. No `~/.claude` path may remain in
  the output (grep-verified).
- **Naming:** plugin `make-it-desktop`; skills `guardrails`, `make-it`, `debug-it`, `nemo-it`,
  `handoff`. Every description says "In Claude Code, use /<cmd> instead." so the namespaced
  skills never compete with the installed commands.
- **Honesty about the sandbox:** skills must never claim a Docker/live check ran when it did
  not. Unrunnable checks are listed as DEFERRED in the handoff, not marked passed.
- **Handoff format = /clear-it's `handoff.md` format** (Goal, Current State, Active Files,
  Changes Made, Failed Approaches, Next Steps) plus a `Source: claude-desktop` line and a
  `Deferred Checks` section. Bundle = project files + `.make-it/app-context.json` + `handoff.md`.
- Desktop sources live in root `desktop/` — outside `.claude/`, so `install.sh` and
  CONTENT_MANIFEST never see them. (Only Task 4 touches `.claude/`; regenerate the manifest
  after `git add`.)
- Plain language in anything user-facing; no jargon without explanation (make-it persona).

## Tasks

### Task 1: Generator + plugin skeleton
Create `desktop/build.sh` (bash, POSIX tools only) that assembles `dist/make-it-desktop/`:
plugin.json from VERSION; for each skill, copy its wrapper `desktop/skills/<name>/SKILL.md`
and the reference files listed in `desktop/skills/<name>/refs.txt` into
`skills/<name>/references/`, applying the import rewrite. Add `dist/` to `.gitignore`.
Add a `--check` mode that fails if any `~/.claude` path remains or a listed ref is missing.
Stub wrappers for all 5 skills (frontmatter + TODO body) so the build runs end to end.
verify: `bash desktop/build.sh && bash desktop/build.sh --check && claude plugin validate dist/make-it-desktop`;
run twice and `diff -r` the outputs → identical.

### Task 2: `guardrails` + `make-it` skills
- `guardrails`: broad description (triggers on building apps, scripts, tools, artifacts, code
  of any kind in Desktop). Body: classify project type (guardrails.md tiers), apply Tier 0 +
  matching tier, AI safety rules if AI features, run the sandbox-runnable subset of
  build-standards (static checks, tests the sandbox can execute), record skipped/deferred
  checks. refs: guardrails.md, build-standards.md, build-verify-security.md, fix-strategies.md,
  expert-personas.md.
- `make-it`: the Preflight→Ideation→Design→Build flow adapted to the sandbox (copy of
  commands/make-it.md as a reference + wrapper that overrides: no Docker preflight, no scaffold
  copy; build what fits; when the design needs Docker/web-app scaffold/deploy, stop after
  design and produce the handoff via the `handoff` skill's format). refs add: design-blueprint.md,
  templates/app-context.md, commands/make-it.md.
verify: build + check + validate pass; grep the output SKILL.md files for "docker compose up"
instructions outside a "defer/handoff" context → none.

### Task 3: `debug-it` + `nemo-it` skills
- `debug-it`: wrapper + commands/debug-it.md as reference (it is environment-agnostic);
  wrapper notes the sandbox can reproduce only what it can run; live-system repros are deferred.
- `nemo-it`: wrapper + commands/nemo-it.md; wrapper restricts to static + dependency modes the
  sandbox can run (no ZAP/SQLMap/live NeMo against a running app); report-only is preserved.
verify: build + check + validate; `nemo-it` wrapper contains no instruction to modify code.

### Task 4: `handoff` skill + `/resume-it` pickup
- `handoff` skill: produces the bundle (see Global constraints) as a downloadable zip; used by
  make-it when it must defer, and directly when a user asks to continue/ship in Claude Code.
  refs: ship-it-guide.md (for what ship-it will need), templates/app-context.md.
- `.claude/commands/resume-it.md` `discover-context` step 0: if `handoff.md` has
  `Source: claude-desktop`, (a) `git init` + initial commit if not a repo, (b) run every item in
  its Deferred Checks section as the first work item (build-verify live checks) before
  suggesting anything else. Minimal diff; nothing else in resume-it changes.
- Bump VERSION (minor), `git add` all new files, regenerate CONTENT_MANIFEST.
verify: build + check + validate; `content-manifest.sh generate . | diff - CONTENT_MANIFEST`
→ empty; resume-it diff touches only step 0.

### Task 5: CI + docs
- Extend CI (new job in a workflow under `.github/workflows/`): run `desktop/build.sh --check`
  and `claude plugin validate` equivalent (if the CLI isn't available in CI, validate JSON +
  frontmatter with a small script) on every PR.
- `desktop/README.md`: what the plugin is, how Rob publishes it to the private marketplace repo
  (`desktop/publish.sh <path-to-make-it-desktop-clone>`: builds, copies dist into
  `plugins/make-it-desktop/`, writes root `marketplace.json`), and how an org admin connects
  GitHub sync. publish.sh only writes to a local clone — it never pushes.
- CHANGELOG entry.
verify: CI green on the PR; publish.sh into a temp dir produces marketplace.json + plugin that
`claude plugin validate` accepts.

## Out of scope (explicit)
- Creating/pushing the private `sealmindset/make-it-desktop` repo and connecting org sync —
  outward-facing; done after merge with Rob's confirmation.
- Porting try-it, wrap-it, argo-it, retrofit-it, git-it, dispatch-it, subagent-it.
- Helix slices 2–6 (rebase onto this after merge).
