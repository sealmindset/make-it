# Git Operations & Repo Hygiene Reference

The day-to-day git discipline that keeps every repo clean, conflict-free, and *always
shippable* — so routine git work never confuses anyone and never negatively impacts the app.
One prescribed model (trunk-based + rebase + fresh-CI + squash-merge), plus the drop / refine /
safe triage for open PRs and stale branches, plus the safety rails that make all of it reversible.

Agent-side discipline; invisible to the vibe-coder. Composes with `worktree-workflow.md`
(isolation, never-main), ship-it (PR→CI→deploy), `parallel-dispatch.md` /
`subagent-driven-development.md` (isolate parallel writers), and `/debug-it` (when CI/build breaks).

---

## The prescribed model (trunk-based)

1. **`main` is always releasable and always green.** Integrate small and often. Never commit
   directly to `main`/`master` — the `no-commit-to-branch` hook enforces it.
2. **Branch per feature, off the latest `main`.** `git fetch origin && git switch -c <branch>
   origin/main`. Keep branches short-lived. For parallel work or a context switch, make a
   **worktree** (`scripts/worktree.sh new <branch>`) — never stash/commit half-done work to switch.
3. **Atomic commits, early and often.** One logical change per commit; each commit should build
   and pass its tests. Write **Conventional Commits**: `type(scope): summary` in the imperative
   (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`). The body explains **why**,
   not just what. Footers: `Co-Authored-By:`, `BREAKING CHANGE:`.
4. **Stage only your own paths.** `git add <specific paths>` — never `git add -A` in a shared
   checkout (it sweeps another session's files). Let the pre-commit hooks gate
   (lint/format/secret-scan/type-check); don't bypass with `--no-verify`.
5. **Update a feature branch by rebasing, not merging.** `git fetch origin && git rebase
   origin/main` keeps history linear and surfaces conflicts early and small.
6. **Push your branch; let CI run.** Re-pushing after a rebase uses `--force-with-lease`, **never
   plain `--force`** (force-with-lease refuses to clobber work you haven't seen).
7. **Fresh CI before merge.** If `main` moved since your last green run, **rebase and re-run CI** —
   never merge on stale green (green CI that predates a later `main` merge proves nothing). Watch
   checks to completion.
8. **Verify before claiming done.** Check the *actual* CI status / merged result / prod — not your
   assumption. "Merged", "green", "deployed" are claims you must confirm against ground truth.
9. **Squash-merge + delete the branch.** One clean commit per feature on `main`; tidy history.
   If the base moved, let mergeability recompute before merging.
10. **After any merge to `main`, everyone rebases.** `git fetch && git rebase origin/main` on
    every live branch so duplicates collapse and conflicts surface early.

---

## Conflict-free tactics

- **Small, frequent PRs** (DORA small-batch) merge faster, conflict less, review better.
- **Rebase frequently** so conflicts stay tiny instead of accumulating into a wall.
- **One feature per branch.** Don't let branches live for weeks.
- **Isolate parallel writers in worktrees** so concurrent edits can't clobber each other.

---

## Drop / refine / safe — the open-PR & stale-branch triage

Run this on any open PR or lingering branch (it's how you keep the PR list and branch list clean):

1. **Superseded? → DROP.** Is its content already on `main` (its net diff vs `main` is empty, or
   the feature shipped via another PR)? Close the PR, delete the branch, record why. Merging it
   would be a no-op that drags in stale state.
2. **Conflicting or stale-CI? → REFINE.** Behind `main`, or its green CI predates a later merge?
   Rebase onto `main`, re-run **fresh CI**, verify, then merge. (Don't merge on the old green.)
3. **Clean + green + still wanted? → SAFE.** Merge it.
4. **Production gate (overrides the above).** Does it touch live/irreversible paths (prod data,
   payments, a real external system)? Verify against a rehearsal/staging target *before* landing,
   regardless of CI. Dev-tool / docs-only changes are low-risk; app-runtime changes are not.

---

## Safety & recovery (everything stays reversible)

- **`--force-with-lease`, never `--force`.** Never rewrite *published/shared* history others have
  based work on (the golden rule of rebasing).
- **`git reflog` is the undo button** for almost everything — recover "lost" commits and branch tips.
- **Undo a commit already on a shared branch with `git revert`,** not a force-push.
- **Branch deletion:** local delete is reflog-recoverable; remote-delete only *merged/superseded*
  branches **you own**. A branch checked out in another worktree is protected — don't fight it.
- **Never `git clean -fdx` without checking** what it nukes (it destroys git-ignored scratch —
  e.g. the SDD ledger; recover that from `git log`).

---

## Repo hygiene (day-to-day cleanup)

- `git fetch --prune` regularly — drop tracking refs for deleted remote branches (local metadata,
  reversible).
- Delete merged local **and** remote branches **you own**; enable delete-branch-on-merge.
- `git worktree prune` removes entries whose directory is gone; `worktree.sh rm <branch>` removes
  finished ones.
- **In a shared / multi-session repo, only touch what you own.** Tool-managed worktrees (audit
  caches, agent-isolation worktrees) and other sessions' branches/worktrees are **off-limits** —
  deleting them is the classic "negative impact." When in doubt, report, don't delete.

---

## The daily loop (quick reference)

```
START   git fetch origin --prune  →  branch/worktree off origin/main
WORK    atomic conventional commits (stage your own paths)  →  hooks gate each commit
SYNC    git fetch && git rebase origin/main  (often; --force-with-lease on push)
LAND    rebase onto main → FRESH CI green → verify → squash-merge → delete branch
AFTER   every other branch: git fetch && git rebase origin/main
TIDY    fetch --prune; delete merged branches you own; prune finished worktrees
```

---

## Never (red flags)

- Commit to `main`/`master` directly · `git add -A` in a shared checkout · `git push --force`
  (use `--force-with-lease`) · rebase a branch others share · **merge on stale CI** (rebase +
  re-run first) · claim "done/merged/green" without verifying ground truth · delete a branch or
  worktree you don't own · `git clean -fdx` without checking what it removes.

## When CI or a build breaks
Don't guess — run the **`/debug-it`** method (root cause first; read the full CI log; check what
changed; both hypothesis families). For several independent failures, fan out with `/dispatch-it`.
