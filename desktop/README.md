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
- **safety** -- instructs Claude how to work safely on the user's computer: secret and sensitive
  files, browser use, screen control, prompt injection, and adding connectors or extensions.

## Operator safety

The rules live in `.claude/make-it/references/operator-safety.md`, shared with Claude Code
(`/make-it`, `/resume-it`, and `/debug-it` load them). Every Desktop skill ships a copy, and the
`safety` skill says when each rule applies in Desktop and Cowork. These are instructions Claude
is told to follow, not a technical block. Section 6 of that file is an admin checklist of settings
that back them up: the Cowork and Chrome permission modes users pick, and the organization's
desktop extension allowlist, connector permissions in custom roles, managed MCP for Claude Code,
and the switch that turns off user-created skills.

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

1. Merge the make-it PR to `main` (bumps `VERSION`).
2. `bash desktop/publish.sh <path-to-local-clone-of-sealmindset/make-it-desktop>` -- builds the
   plugin, syncs it into `<clone>/plugins/make-it-desktop/` (removing anything stale there), and
   writes `<clone>/.claude-plugin/marketplace.json` (including the bumped version). It only
   writes inside that local clone; it never runs `git commit` or `git push`.
3. In the clone: commit on a branch, push the branch, and open a PR against the clone's default
   branch. The version bump has to land in `plugins/make-it-desktop/.claude-plugin/plugin.json`
   for the next step to matter.
4. Merge that PR. **A merged PR that changes the plugin version is what triggers automatic sync**
   (per the Claude help center) -- a direct push to the default branch does not trigger it. If
   auto-sync isn't configured, or you want the update sooner, an org admin clicks **Update** on
   the marketplace in Organization settings to sync manually.

**Caution:** GitHub-synced plugin marketplaces have no separate approval gate. A sync replaces
the marketplace's plugin list with whatever is in the repo at that moment -- once synced (auto or
manual), the new version is what everyone installing or already running "installed by default"
sees. There is no admin review step between sync and rollout; review happens at the PR stage
above, before merge.

## One-time org admin setup

1. Confirm Cowork and Skills are enabled for the organization.
2. Create the private (or internal) GitHub repo, `sealmindset/make-it-desktop`.
3. Install the Claude GitHub App on that repo **first** -- sync reads the repo through the app,
   not through Claude Code.
4. In Organization settings > Plugins & skills > Marketplaces > Add, choose "Sync from GitHub"
   and point it at the repo.
5. Set the `make-it-desktop` plugin to "Available to install" or "Installed by default", per how
   widely it should roll out.
6. Optional: turn on auto-sync (requires GitHub admin rights on the repo; a GitHub org admin may
   need to separately approve the app's webhook permission).

The marketplace reads `.claude-plugin/marketplace.json` at the repo root -- that path is inferred
from the plugin reference, so confirm it on the first manual **Update** rather than assuming.

Once set up, every future release is: `publish.sh` into a fresh branch of the clone -> commit,
push, open a PR -> merge -> auto-sync (or admin clicks Update).
