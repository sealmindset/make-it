---
name: git-it
description: Day-to-day git operations and repo hygiene done right — keep main always-green and shippable, branches short-lived, history clean, and everything conflict-free and reversible. Prescribes one proven model (trunk-based + branch-per-feature off main + atomic conventional commits + rebase with --force-with-lease + fresh-CI-before-merge + squash-merge + delete branch + worktree isolation), runs the drop/refine/safe triage on open PRs and stale branches, and prunes safely without touching other sessions'/tools' work. Use to commit/push/rebase/merge correctly, clean up branches & PRs, or resolve "what's safe to land/drop."
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Skill
---

<objective>

Make routine git work clean, clear, conflict-free, and safe — so nothing ever confuses the team
or negatively impacts the app. One prescribed workflow, the drop/refine/safe triage for the PR &
branch backlog, and reversible-by-default safety rails.

Full doctrine: `~/.claude/make-it/references/git-operations.md`.

</objective>

# /git-it -- everyday git, done right

**Prime directive:** never negatively impact the app or another session's work. When an action
isn't provably safe and reversible, report instead of acting.

## The prescribed model (trunk-based)
`main` is always green & releasable; never commit to it directly (the `no-commit-to-branch` hook
enforces it). Branch per feature off the latest `origin/main` (or a worktree for parallel work).
Atomic **Conventional Commits** (`type(scope): summary`, imperative, body says *why*). **Stage only
your own paths** (`git add <paths>`, never `-A` in a shared checkout). Update by **rebase**, push
with **`--force-with-lease`** (never `--force`). **Fresh CI before merge** — if `main` moved,
rebase and re-run; never merge on stale green. **Verify** the real state before claiming done.
**Squash-merge + delete the branch.** After any merge, every other branch rebases onto `main`.

## Daily loop
```
START  git fetch origin --prune  →  branch/worktree off origin/main
WORK   atomic conventional commits (your own paths only)  →  hooks gate each commit
SYNC   git fetch && git rebase origin/main  (often; --force-with-lease on push)
LAND   rebase → FRESH CI green → verify → squash-merge → delete branch
TIDY   fetch --prune; delete merged branches you own; prune finished worktrees
```

## Open-PR / stale-branch triage (drop / refine / safe)
For each open PR or lingering branch:
1. **Superseded** (content already on `main` / shipped elsewhere; net diff empty) → **DROP**:
   close + delete branch, record why.
2. **Conflicting or stale-CI** (behind `main`, or green predates a later merge) → **REFINE**:
   rebase onto `main`, re-run **fresh CI**, verify, then merge.
3. **Clean + green + still wanted** → **SAFE**: merge.
4. **Production gate** (live/irreversible paths) → verify against rehearsal/staging *before*
   landing, regardless of CI. Dev-tool/docs = low risk; app-runtime = not.

## Safety & recovery
`--force-with-lease` never `--force`; never rewrite shared history. `git reflog` recovers almost
anything; undo a shared commit with `git revert`, not force-push. Local branch delete is
reflog-recoverable; remote-delete only merged/superseded branches **you own**; never `git clean
-fdx` without checking (it nukes git-ignored scratch like the SDD ledger).

## Shared / multi-session repos (critical)
Only touch what **you** own. Tool-managed worktrees (audit caches, agent-isolation worktrees) and
other sessions' branches/worktrees are off-limits — deleting them is the classic negative impact.
A branch checked out in another worktree is protected; don't fight it. When in doubt → report.

## When CI/build breaks
Run the `/debug-it` method (root cause first; read the full log; check what changed). Several
independent failures → `/dispatch-it`.

See `git-operations.md` for the full model, conflict-free tactics, commit standard, and red flags.
