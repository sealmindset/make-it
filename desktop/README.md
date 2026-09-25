# make-it-desktop

A Claude Code plugin that brings make-it's guardrails to Claude Desktop and Cowork, where there
is no shell, no Docker, and no git. It's generated from the same source of truth as the
`/make-it` skill suite -- one set of rules, two runtimes.

## Skills

- **guardrails** -- applies the tiered quality/security rules to anything built in Desktop or
  Cowork (apps, scripts, artifacts, any code).
- **make-it** -- the guided idea-to-app flow, adapted to what the sandbox can actually do.
- **debug-it** -- root-cause debugging for whatever the sandbox can reproduce.
- **nemo-it** -- security attestation, limited to the static and dependency checks the sandbox
  can run.
- **handoff** -- packages a project (files + `.make-it/app-context.json` + `handoff.md`) so the
  user can continue it in Claude Code, where `/resume-it` picks it up.

## Sandbox limits and handoff

Desktop and Cowork can't run Docker, can't call `git` or `gh`, and can't do a live
build-and-verify against a running app. Any skill that hits one of those limits stops, records
what it couldn't check as **deferred**, and offers the `handoff` skill instead of pretending the
check passed. In Claude Code, `/resume-it` sees a handoff bundle's `Source: claude-desktop` line
and runs every deferred check first, before anything else.

## Source layout

- `desktop/skills/<name>/SKILL.md` -- the Desktop-specific wrapper (sandbox overrides only; never
  restates the rules).
- `desktop/skills/<name>/refs.txt` -- which files from `.claude/make-it/references/` and
  `.claude/commands/` this skill needs.
- `desktop/build.sh` -- copies those reference files into `dist/make-it-desktop/skills/<name>/references/`,
  rewrites `~/.claude/...` paths to relative `references/...` links, and writes
  `dist/make-it-desktop/.claude-plugin/plugin.json`.

**`dist/make-it-desktop/` is generated and gitignored. Never hand-edit it** -- edit the wrapper or
`refs.txt` and rebuild. The rules themselves live only in `.claude/make-it/references/`; nothing
here paraphrases or copies them by hand.

## Build and check locally

```bash
bash desktop/build.sh              # writes dist/make-it-desktop/
bash desktop/build.sh --check      # fails on a lingering ~/.claude path, a broken references/
                                    # link, or a disallowed bin/ directory
bash desktop/test-build.sh         # self-tests: determinism, --check, rewrite rules
claude plugin validate dist/make-it-desktop
```

## Release steps (Rob)

1. Merge the PR to `main`.
2. `bash desktop/publish.sh <path-to-local-clone-of-sealmindset/make-it-desktop>` -- builds the
   plugin, syncs it into `<clone>/plugins/make-it-desktop/` (removing anything stale there), and
   writes `<clone>/.claude-plugin/marketplace.json`. It only writes inside that local clone; it
   never runs `git commit` or `git push`.
3. In the clone: review the diff, commit, and push.
4. The org's marketplace sync picks up the new version on the next sync (manual, or automatic on
   merge to the clone's default branch). An org admin approves the new version before it reaches
   everyone.

## One-time org admin setup

1. Create a private (or internal) GitHub repo, `sealmindset/make-it-desktop`.
2. In Organization Settings, add it as a plugin marketplace via GitHub sync.
3. Install the Claude GitHub App on that repo so Claude Code can sync it.

Once set up, every future release is just step 2 above (`publish.sh` + commit + push).
