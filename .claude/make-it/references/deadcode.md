# Dead Code -- evidence, grading, deletion cadence, log

The single source of truth for finding and removing dead code. `/deadcode-it` runs all of it.
Build-standards checks Q14 and Q15 run the §2 Evidence pass **report-only** (they never delete or
edit anything), and `/retrofit-it` Discovery does the same.

**The rule:** prove "unused" with tools AND a search, delete in small batches, verify after each
against the code that actually ships, log every removal. When unsure, it stays a **candidate** --
logged, not deleted.

---

## 1. Keep-list (never deleted, by anyone)

A path is **kept** when any of these holds. Kept paths are reported, never graded SAFE or CAUTION.

1. **Scaffold-owned** (only when `.make-it/app-context.json` exists -- in any other repo a path
   that happens to match the scaffold means nothing) -- its path relative to the project root
   also exists under `~/.claude/make-it/scaffolds/fastapi-nextjs/` (or
   `scaffolds/overlays/<variant>/` when `app-context.json` names a variant). These are
   capabilities the app ships with on purpose (AI Instructions pages, notifications, PWA parts,
   DataTable options) even when nothing uses them yet. Report them as "built-in features not
   used yet". Dependency manifests (`package.json`, `requirements.txt`, `pyproject.toml`) are
   judged per entry, not by path: a dependency is scaffold-owned only if the scaffold's own
   manifest lists it.
2. **Kept by the user's call** -- listed under `### Kept (user's call)` in any earlier run of
   `docs/DELETION_LOG.md` on **any local branch**, dropped cleanups included (read
   `git show <branch>:docs/DELETION_LOG.md` for every branch in
   `git for-each-ref --format='%(refname:short)' refs/heads`). Its `in use` candidates (including
   ones a red batch proved) count the same way: not dead, not re-tried. Never ask about it again;
   report it in the count only, and copy each such row into this run's log (Kept or Candidates,
   with "from `<branch>`"), so the decision survives if that branch is ever removed.
3. **Generated or vendored** -- `node_modules/`, `.next/`, `dist/`, `build/`, `venv/`, `.venv/`,
   `__pycache__/`, `mock-services/`, `alembic/versions/`, lockfiles, codegen output (a file with
   a "generated"/"do not edit" header, or the output path of a codegen config).
4. **Untracked** -- anything `git ls-files --others --exclude-standard` lists (work in progress
   with no history: deleting it couldn't be undone). Never a candidate, never edited. Only
   tracked files (`git ls-files`) are candidates.

## 2. Evidence pass (tools, in parallel)

Detect the stack per directory that holds a `package.json` or Python sources. Run every tool that
applies **in parallel** (one Bash call per tool, same message), **on the host** (a container can't
host them: the scaffold's frontend image holds only the built app, and no image has `npx`/`uvx`).
Save raw output to a scratch directory outside the repo (inside it, a file named `knip.json` is
read by knip as its config).

JS/TS tools need the project's packages installed on the host. Report-only callers (Q14, Q15,
`/retrofit-it` Discovery) use **existing installs only** -- they never install anything, and a
tool without its install is "not run: packages not installed". `/deadcode-it` may install them
with the project's own package manager (§5.3 table, frozen form) when `node_modules/` is
missing; it never re-installs over an existing one.

| Stack | Tool | Command (raw output to scratch) | Finds |
|-------|------|---------------------------------|-------|
| JS/TS | knip | `npx -y knip --reporter json` | unused files, exports, types, deps, devDeps, binaries (its Next.js plugin knows `app/` convention files) |
| JS/TS | depcheck | `npx -y depcheck --json` | unused and missing deps (second opinion on knip) |
| JS/TS | ts-prune | `npx -y ts-prune` | unused exports (archived upstream: corroboration only, never the sole evidence) |
| JS/TS | tsc | `npx --no tsc --noEmit --noUnusedLocals` | unused imports and locals |
| JS/TS | eslint | `node_modules/.bin/eslint . --report-unused-disable-directives -f json` -- only when `node_modules/.bin/eslint` exists and its config matches its version (`eslint.config.*`, or `.eslintrc*` with eslint < 9); otherwise "not run: <reason>" | unused vars (per the project's config), stale `eslint-disable` comments |
| Python | ruff | `uvx ruff check --no-cache --select F401,F811,F841 --output-format json <src>` | unused imports, redefinitions, unused locals |
| Python | vulture | `uvx vulture <src> --min-confidence 60 --exclude <§1.3 dirs>` | unused functions, classes, attributes, variables (confidence %) |
| Python | deptry | `requirements.txt` → `uvx --with-requirements requirements.txt deptry . --json-output <scratch>/deptry.json`; `pyproject.toml` only → `uv pip compile pyproject.toml -q -o <scratch>/req.txt` then `uvx --with-requirements <scratch>/req.txt deptry . --json-output <scratch>/deptry.json` (run from the manifest's directory; nothing is written into the project) | unused deps (DEP002 only; DEP001 "missing" is not dead code) |

deptry needs the project's packages in its environment or it can't map `PyYAML` → `yaml` and
reports false hits; the commands above give it them. A tool that can't run (no network, no
install, crash) is recorded as **not run, with the reason** -- never as "no findings". Tools for a
stack the project doesn't have are "not applicable", not "not run", and aren't reported as gaps. Most of
these tools exit non-zero when they find something (knip 1, depcheck 255, tsc 2, ruff 1,
vulture 3, deptry 1): a tool ran if it produced its report. `<src>` is the same for ruff and
vulture: every Python source directory outside the keep-list. Merge the outputs into one
candidate list: item, kind (import / local / export / file / dependency / test helper),
location, which tools flagged it.

## 3. AI review (prove each candidate)

For every candidate outside the keep-list, search the **whole repo, code and non-code**, and
record what was searched and what it found. Many candidates → read-only subagents, one per kind,
in parallel. A candidate survives as dead only when every check comes back empty:

1. **Exact name** -- `grep -rn` the symbol, file stem, or package name across the repo,
   including tests, docs, `*.yml`, `Dockerfile*`, `docker-compose*`, `Makefile`, `package.json`
   scripts, `pyproject.toml`, `.github/`, `scripts/`.
2. **String and path forms** -- the name in quotes; the path without extension; kebab, snake and
   camel variants; the route a page file serves. Grep can't see dynamic references, so look for
   them by shape: `import(` with a template or variable, `require(` with a variable,
   `importlib`, `getattr`/`setattr`, `__import__`, registry dicts or maps keyed by name,
   `entry_points`, plugin lists, and commands built at run time (`subprocess`/`os.system`/
   `child_process` calls, `python -m <var>`, `npx <var>`). A built name you can work out (`"pyfl" +
   "akes"`) that names the package → in use; one you can't work out but that could name it →
   CAUTION, not SAFE.
3. **Framework convention** -- Next.js `app/**/{page,layout,route,loading,error,global-error,not-found,global-not-found,forbidden,unauthorized,template,default}.*`,
   metadata files (`sitemap`, `robots`, `manifest`, `icon`, `apple-icon`, `opengraph-image`,
   `twitter-image`), `middleware.*`, `proxy.*`, `instrumentation.*`, `next-env.d.ts`, `sw.ts`,
   `next.config.*` -- and anything else knip's Next.js plugin treats as an entry (`npx knip
   --debug` lists them); FastAPI/Flask decorated handlers (`@router.*`, `@app.*`), dependencies
   used via `Depends(...)`, startup/lifespan hooks; pytest fixtures and `conftest.py`; pydantic
   validators and model/settings fields (read by name from env or JSON); SQLAlchemy models and
   event listeners; Alembic `upgrade`/`downgrade`; Celery tasks; CLI entry points. Also exports
   the framework reads by name: Next.js `dynamic`, `revalidate`, `runtime`, `fetchCache`,
   `metadata`, `generateMetadata`, `generateStaticParams`, `viewport`, middleware/proxy `config`;
   default exports of any `*.config.*`; Storybook default `meta` and story exports.
4. **Build and release time** -- referenced by CI, a Dockerfile, a compose command, a
   `package.json`/`pyproject.toml` script or bin, a codegen or docs pipeline.
5. **Dependencies used without an import** -- the most common false positive (on the scaffold
   backend, all 10 of deptry's DEP002 hits were these):
   - run as a command: servers and dev tools invoked by a Dockerfile, compose, CI, pre-commit, a
     script or the hosting platform (uvicorn, gunicorn, pytest + plugins, ruff, mypy, eslint,
     prettier, tsc);
   - named in a config: eslint/prettier/postcss/tailwind/babel/jest/vitest/playwright plugins,
     `@types/*`, Next.js peer deps;
   - loaded by a framework, a URL or the environment: DB drivers named in a connection string
     (asyncpg, aiosqlite, psycopg), `python-multipart` (FastAPI forms and uploads), APM and
     instrumentation agents (newrelic, ddtrace, sentry) -- the connection string or start
     command may live only in `.env` or the hosting platform, where grep can't see it;
   - imported under another name: `PyJWT` → `jwt`, `Pillow` → `PIL`, `python-dotenv` → `dotenv`,
     `beautifulsoup4` → `bs4`. Grep the import name, not just the package name.
6. **Only its own tests** -- if the only references are its tests, it is dead code, but removing
   it removes tests too: grade CAUTION, never SAFE.
7. **Imported for its effect** -- these run code when loaded (register routes, models, signals,
   plugins) and tests rarely notice them gone: CAUTION, never SAFE.
   - an import of a module that lives in this project (a file or package in the repo:
     `import app.models.reports`, `from . import signals`) or of a third-party package imported
     whole (`import some_plugin`);
   - an import inside a function body, or a JS bare import (`import "./x"`);
   - a named import from a module in this project (`from app.models.invoice import Invoice`)
     when it is the only import of that module anywhere in the repo: removing it stops the
     module loading;
   - **any import in an `__init__.py`** is a re-export (public API): DANGER, unless
     `from <package> import <Name>` and `<package>.<Name>` both grep empty -- then CAUTION.

   Standard-library modules (`import json`, `import os`) don't register anything when loaded: an
   unused one is an ordinary unused import. `ruff --fix` deletes effect imports (it turns
   `def ready(): from . import signals` into `pass`), so ruff's fix is never applied -- remove
   only the specifiers this check clears, by hand.
8. **Used in its own file** -- an export nothing imports may still be used inside its own file
   (knip and ts-prune report "not imported elsewhere", not "unused"). Grep the file itself: used
   there → not dead code; log it as a candidate "exported but used in its own file" (dropping
   only the `export` keyword is a refactor, out of scope).

## 4. Grade: SAFE / CAUTION / DANGER

| Grade | What qualifies | What happens |
|-------|----------------|--------------|
| **SAFE** | Flagged by ruff, tsc, eslint, knip, depcheck or deptry (ts-prune and vulture never count on their own), every §3 check empty, and one of: unused import that §3.7 cleared; unused local whose right-hand side is a literal or a plain name (a right-hand side that calls, awaits or builds anything does work: delete only the binding and keep the expression -- `save(order)`, not `result = save(order)`; that is the one edit a cleanup batch makes beyond deleting); unused export of an internal module that §3.8 cleared; unused dependency, only when the §5.1 verify set starts the app the way production does (a Docker rebuild that passes its health checks) and the package is in no §3.5 class; JS/TS test helper nothing calls, inside a file that stays | Deleted automatically in batches (§5) |
| **CAUTION** | Whole files, components, pages' children, API routes, shared utilities; anything a dynamic-loading shape elsewhere (§3.2) could plausibly reach but you can't tell whether it does; used only by its own tests (§3.6); §3.7 effect imports; a test helper that is its own file, and every Python test helper (only vulture finds them); anything only ts-prune or vulture flags; an unused dependency that doesn't meet the SAFE bar | One batched ask (§6); deleted only if picked |
| **DANGER** | Configs, entry points, framework-convention files and exports (§3.3), public API (`package.json` `exports`/`main`/`bin`, `__all__`, `__init__.py` re-exports, a published package), anything §3.4 found, migrations, auth/RBAC/security code | Never deleted. Listed as a candidate with the reason |

Torn between two grades → the higher one. vulture's 100%-confidence items (unused function
parameters, unreachable code) are refactors, not dead code: candidates, never deleted.

**Weak verify set.** If the §5.1 verify set has neither a test run nor a build or type-check, SAFE
is limited to unused imports and locals; everything else goes to CAUTION, and the report says why.

**In use (not graded).** A §3 check that finds a real use -- a dynamic import whose pattern
matches it, a `getattr` whose name it fits, a command, a config entry, an import under another
name -- means the tool was wrong: it is not dead code. Drop it from grading and log it under
Candidates as `in use: <where>`, so the next run doesn't re-investigate it. An item that is also
DANGER (e.g. a `package.json` `main`) is logged as DANGER.

## 5. Deletion cadence (SAFE, then picked CAUTION)

1. **Where checks run.** Every verify -- the baseline and the one after each batch -- runs
   against the code as it is now, never an older build:
   - **The app runs in Docker** (a compose file builds its services): first check the settings
     point only at this machine -- every host in `docker compose config`'s environment values is
     a compose service name, `localhost` or `127.0.0.1`. A host anywhere else (a shared or real
     database, a live API) → stop, with nothing changed and no branch made: "Your app's settings point at <host>, so I
     won't start it for checks. If that setting is only meant for the live app, point it at your
     own machine for local runs and run /deadcode-it again." Then, before **every** verify, `docker compose up -d --build --wait <app services>`
     (this also runs the frontend's production build), and run the test commands in those fresh
     containers (`docker compose exec <service> pytest`, ...). Never `exec` into a container that
     was built before the batch -- it still holds the old code.
   - **Otherwise** run the set on the host.
2. **Baseline green.** The project's full verify set: backend tests, frontend build, type-check,
   lint (`pytest`, `npm run build`, `npm run type-check`, `npm run lint`, or what `package.json`
   defines, plus the build/test commands CI runs). Never run a step that releases, deploys,
   publishes, tags, pushes, sends anything, or migrates a real database -- even when CI runs it;
   name it in the log as "not run (release step)". Security and audit scans (`npm audit`,
   `pip-audit`, gitleaks, trivy) are not part of it: a newly published advisory isn't a broken
   app. Red baseline → stop. Nothing is deleted on a red baseline; hand the failure to `/debug-it`.
3. **One category per batch**, in this order: unused imports/locals → unused dependencies →
   unused exports → unused test helpers → picked CAUTION items. At most ~20 items per batch.
   **Delete only.** No renames, moves, reformatting, dedupes or "while I'm here" edits in a
   cleanup batch. Remove a dependency by deleting its manifest entry by hand (keep the file
   valid: a JSON entry may share a line with others; `npm uninstall` reformats `package.json`),
   then update the lockfile with the project's own package manager, and verify that batch on a
   fresh frozen install (in Docker, the `--build` above):

   | Lockfile | Update the lock | Fresh install to verify |
   |----------|-----------------|-------------------------|
   | `package-lock.json` | `npm install` | `npm ci` |
   | `pnpm-lock.yaml` | `pnpm install` | `pnpm install --frozen-lockfile` |
   | `yarn.lock` | `yarn install` | `yarn install --frozen-lockfile` (Yarn 2+: `--immutable`) |
   | `uv.lock` | `uv lock` | `uv sync --locked` |
   | `poetry.lock` | `poetry lock --no-update` | `poetry install --sync` |
   | none (`requirements.txt`) | -- | a new venv in the scratch directory from the file |

   Any other package manager → that dependency goes to CAUTION.
   After the imports/locals batch, re-run the evidence tools once: removing an import can leave
   what it imported unused. New candidates go through §1, §3 and §4 like the rest.
4. **Re-run the verify set immediately.**
   - Green → write the batch's log rows (§7; rows are written only now, never before a green
     verify), stage **only** the paths the batch deleted or edited, its manifest and lockfile,
     and `docs/DELETION_LOG.md` (never `git add -A`), and commit:
     `chore(deadcode): remove <N> unused <category>`. If a commit hook changes a file (a project
     `ruff --fix` hook deletes effect imports the run kept), restore that file from the last
     commit, take it out of the batch (log it: "kept: the project's commit hook would also edit
     this file"), re-run the verify set, and commit the rest. Never `--no-verify`, never add an
     ignore comment. The report names the hook as something a developer should look at.
   - Red → `git restore --staged --worktree -- :/` (`:/` is the repo root, whatever folder you
     are in) back to the last commit. A dependency batch also reinstalls from the restored
     manifest (the fresh-install column above, or the `--build`) before anything is verified
     again, or the next batch fails for the wrong reason. Then split the batch in halves and
     retry each half until the item that breaks it is found. That item is **in use** (the
     failure is the proof): log it as `in use: <failing check>`, never offer it for removal, and
     the rest of the batch continues. Three more red verifies in one category after its first →
     stop that category and report it.
5. Never make a check pass by weakening it: no new lint ignores, no skipped or deleted failing
   tests, no relaxed tool configs. A tool's false positive goes in the log as a candidate with the
   reason, not into an ignore file.

## 6. The CAUTION ask

One ask for the whole run (approval-block.md: consequential; the user picks the specific items,
never a plain yes). AskUserQuestion, up to 4 questions, ranked by strength of evidence; the rest
stay candidates. A multi-item question is `multiSelect: true` with up to 3 items and a last
option "Keep all of these" (picked, alone or with others, it keeps that question's items) -- 12
items per ask at most. A single item is one single-select question (`multiSelect: false`) with
the options "Remove it" / "Keep it". Open the ask with the approval-block.md points that apply to
the whole set: what is unusual about these items (why they aren't SAFE) and the one thing to
check. Each option in plain words:

- **label** -- what it is ("Old 'Reports' chart", "Unused 'lodash' package")
- **description** -- the evidence ("no page links to it; nothing loads it by name; knip and
  ts-prune both flag it"), what removing it changes for the user ("nothing you can see"), and the
  undo ("one step to bring it back").

When the user answers, unpicked items go under `### Kept (user's call)` and are never asked about
again. An answer with nothing picked is an answer. If the ask is dismissed or skipped, nothing was chosen: the items stay under Candidates
("CAUTION, not yet decided") and are asked about on the next run.

## 7. Deletion log -- `docs/DELETION_LOG.md`

Created on the first run with a `# Deletion Log` title and one line saying what it is. Each run
appends one section; each batch commit carries its own rows with `this batch` in the Commit
column, and the final log commit (the skill's `log` step) replaces those with the short hashes.

```markdown
## <YYYY-MM-DD> -- /deadcode-it

Started from: `<starting branch>` at <short sha>. Cleanup branch: `<cleanup branch>`.
Baseline: <verify set> green (<where: host / rebuilt containers>). Tools: knip ✓, depcheck ✓,
tsc ✓, eslint ✓, ruff ✓, vulture ✓, deptry ✗ (not run: <reason>).

### Removed
| Item | Kind | Grade | Why it's safe (tools + search) | Replaced by | Verified | Commit |
|------|------|-------|--------------------------------|-------------|----------|--------|
| `frontend/lib/old-format.ts` | file | CAUTION (user picked) | knip+ts-prune; 0 refs incl. string/path forms, CI, scripts | -- | build ✓ tests ✓ | abc1234 |

### Candidates (not removed)
| Item | Grade | Reason |
|------|-------|--------|

### Kept (user's call)
| Item | Asked on |
|------|----------|

Built-in features not used yet: <N> (scaffold-owned, never removed).
```

"Replaced by" stays `--`: this cleanup deletes, it never dedupes (duplicates are listed as
candidates with "duplicate of <path>" as the reason).

## 8. The Q15 result line (TODO.md)

Q14, Q15 and `/deadcode-it` share one line in `TODO.md`, always starting with the same marker so
each can find and replace it:

`- [ ] Q15 dead code (<YYYY-MM-DD>): <N> unused files, exports, dependencies or imports found, none removed -- run /deadcode-it`

with `0 found` or `not run: <reason>` in place of the count when that is the result. Each writer
replaces the existing marker line rather than adding another. `/resume-it` reuses the line while
no tracked file has changed since its date (`git log --since=<date> --oneline -- . ':!docs' ':!TODO.md'`
is empty) and re-runs the §2 pass only otherwise.
