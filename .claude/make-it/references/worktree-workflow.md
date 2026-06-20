# Worktree & Commit-Discipline Reference

Every /make-it project uses **git worktrees + commit discipline** as its default working
model. The goal: never commit half-done work to switch context, never let an out-of-turn
commit break the app on the default branch, and let parallel agents/sessions work without
clobbering each other.

This is **automated for agents and advanced developers** and stays mostly invisible to the
vibe-coder end user — they keep describing what they want; the isolation happens underneath.

---

## Why worktrees (the one-paragraph version)

A worktree gives each branch its **own physical directory** linked to the same repository.
Instead of `git stash` / `git checkout` churn (which forces you to park or commit unfinished
work just to look at another branch), you `cd` into a sibling folder where that branch is
already checked out. Switch context instantly; leave the current work exactly as it is.

Worktrees give you *isolation*. They do not, by themselves, stop bad commits — that's
**commit discipline** (below). The two together are the policy.

---

## Commit discipline (the rules that stop slop)

1. **Never commit to the default branch.** `main`/`master` stays deployable at all times.
   The scaffold enforces this with a `no-commit-to-branch` pre-commit hook.
2. **One feature per branch.** Branch fresh off the latest default branch.
3. **Gate before you commit.** Lint + build + relevant tests must be green. The pre-commit
   hooks (ruff/eslint/prettier/gitleaks) run automatically; don't bypass with `--no-verify`.
4. **Stage only your own paths.** Prefer `git add <specific paths>` over `git add -A` in a
   shared checkout. Never sweep another session's unfinished files into your commit.
5. **Don't commit unfinished work to switch context.** Make a worktree instead and leave the
   current one untouched.
6. **Rebase after every merge.** When a branch lands on the default branch, the others
   `git fetch && git rebase origin/<default>` so duplicates collapse and conflicts surface early.

---

## Per-worktree runtime isolation (the footgun this prevents)

Dockerized /make-it apps use fixed host ports and named volumes. If two worktrees both run
`docker compose up`, they collide on ports, containers, and — worst case — **the same
database volume** (silent corruption). So isolation is mandatory, and it's automatic:

- **Compose is parameterized.** `docker-compose.yml` declares
  `name: ${COMPOSE_PROJECT_NAME:-<slug>}` and every host port is `${PORT_VAR:-default}`
  (mappings *and* the browser-facing URLs, so auth redirects don't loop in a worktree).
- **The helper seeds an isolated `.env` per worktree.** `scripts/worktree.sh new <branch>`
  derives a stable `COMPOSE_PROJECT_NAME` and **offsets every host port** by a deterministic
  amount (hashed from the branch name), writing them into the new worktree's `.env`.

Result: `docker compose --profile dev up --build` "just works" in any worktree with zero
collisions and zero manual edits. Each worktree gets its own containers, network, and DB
volume namespace.

> Each worktree is a separate directory, so it needs its own `node_modules` / virtualenv and
> its own `.env` (which is gitignored). The helper copies `.env` from the main checkout; run
> the install step once per worktree.

---

## The helper: `scripts/worktree.sh`

Stack-agnostic. Ships in every generated project.

```bash
scripts/worktree.sh new <branch> [base-ref]   # create an isolated worktree + seeded .env
scripts/worktree.sh list                       # show all worktrees
scripts/worktree.sh rm <branch> [--force]      # remove a worktree and prune
```

Worktrees are created as **siblings** of the main checkout, under
`../<repo>-worktrees/<branch>/` (kept outside the working tree to avoid nested-repo and
tool-scan weirdness; the `*-worktrees/` pattern is gitignored as a backstop).

`new` does, in order: create the worktree (new branch off `base-ref`, default `HEAD`) →
copy `.env` (or `.env.example`) → compute a branch-stable port offset → write
`COMPOSE_PROJECT_NAME` + offset `*_PORT` values into the worktree `.env` → print next steps.

---

## How the skills use this

- **/make-it** — scaffolds `scripts/worktree.sh`, the `no-commit-to-branch` hook, and the
  parameterized compose into every project; after the initial commit on the default branch,
  feature work moves to a branch/worktree.
- **/resume-it** — before starting a new line of work, create (or reuse) a worktree for it;
  never build on top of unfinished work in the main checkout.
- **/ship-it** — ships the current worktree's branch; the default branch stays clean.
- **/wrap-it** — offer to `rm` finished worktrees and prune.

When working as an agent: if you need to switch tasks, **make a worktree** — do not stash or
commit unfinished work, and do not commit to the default branch.

---

## Build-verify

See `build-standards.md` checks **VC01–VC05** (helper present, no-commit-to-main hook,
worktree-safe compose, worktrees gitignored, branch discipline documented). For non-Docker
project types (cli, library), the runtime-isolation checks are N/A but the branch/commit
discipline still applies.
