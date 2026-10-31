# Dead Code -- evidence, grading, deletion cadence, log

The single source of truth for finding and removing dead code. `/deadcode-it` runs all of it;
build-standards checks Q14 (lint-level fix) and Q15 (report-only count) run the parts they name;
`/retrofit-it` Discovery runs the Evidence pass report-only.

**The rule:** prove "unused" with tools AND a search, delete in small batches, verify after each,
log every removal. When unsure, it stays a **candidate** -- logged, not deleted.

---

## 1. Keep-list (never deleted, by anyone)

A path is **kept** when any of these holds. Kept paths are reported, never graded SAFE or CAUTION.

1. **Scaffold-owned** -- its path relative to the project root also exists under
   `~/.claude/make-it/scaffolds/fastapi-nextjs/` (or `scaffolds/overlays/<variant>/` when
   `app-context.json` names a variant). These are capabilities the app ships with on purpose
   (AI Instructions pages, notifications, PWA parts, DataTable options) even when nothing uses
   them yet. Report them as "built-in features not used yet".
2. **Kept by the user's call** -- listed under `### Kept (user's call)` in any earlier run of
   `docs/DELETION_LOG.md`. Never ask about it again; report it in the count only.
3. **Generated or vendored** -- `node_modules/`, `.next/`, `dist/`, `build/`, `venv/`,
   `__pycache__/`, `mock-services/`, `alembic/versions/`, lockfiles, codegen output (a file with
   a "generated"/"do not edit" header, or the output path of a codegen config).

## 2. Evidence pass (tools, in parallel)

Detect the stack per directory that holds a `package.json` or Python sources. Run every tool that
applies **in parallel** (one Bash call per tool, same message), saving raw output to a scratch
directory outside the repo (inside it, a file named `knip.json` is read by knip as its config). Run where the dependencies are installed: on the host after
`npm ci` / a venv install, or inside the running container (`docker compose exec <service> ...`).

| Stack | Tool | Command (raw output to scratch) | Finds |
|-------|------|---------------------------------|-------|
| JS/TS | knip | `npx -y knip --reporter json` | unused files, exports, types, deps, devDeps, binaries (its Next.js plugin knows `app/` convention files) |
| JS/TS | depcheck | `npx -y depcheck --json` | unused and missing deps (second opinion on knip) |
| JS/TS | ts-prune | `npx -y ts-prune` | unused exports (archived upstream: corroboration only, never the sole evidence) |
| JS/TS | tsc | `npx tsc --noEmit --noUnusedLocals` | unused imports and locals |
| JS/TS | eslint | `npx eslint . --report-unused-disable-directives -f json` | unused vars (per the project's config), stale `eslint-disable` comments |
| Python | ruff | `uvx ruff check --select F401,F811,F841 --output-format json <src>` | unused imports, redefinitions, unused locals |
| Python | vulture | `uvx vulture <src> --min-confidence 60 --exclude <keep-list dirs>` | unused functions, classes, attributes, variables (confidence %) |
| Python | deptry | `cd <dir with requirements.txt or pyproject.toml> && uvx deptry . --json-output <scratch>/deptry.json` | unused deps (DEP002 only; its exit code is 1 whenever it finds anything) |

A tool that can't run (no network, no install, crash) is recorded as **not run, with the
reason** -- never as "no findings". Merge the outputs into one candidate list: item, kind
(import / local / export / file / dependency / test helper), location, which tools flagged it.

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
   `entry_points`, plugin lists.
3. **Framework convention** -- Next.js `app/**/{page,layout,route,loading,error,not-found,template,default}.*`,
   `middleware.*`, `instrumentation.*`, `sw.ts`, `next.config.*`; FastAPI/Flask decorated handlers
   (`@router.*`, `@app.*`), dependencies used via `Depends(...)`, startup/lifespan hooks; pytest
   fixtures and `conftest.py`; pydantic validators and model/settings fields (read by name from
   env or JSON); SQLAlchemy models and event listeners;
   Alembic `upgrade`/`downgrade`; Celery tasks; CLI entry points.
4. **Build and release time** -- referenced by CI, a Dockerfile, a compose command, a
   `package.json`/`pyproject.toml` script or bin, a codegen or docs pipeline.
5. **Dependencies used without an import** -- the most common false positive (on the scaffold
   backend, all 10 of deptry's DEP002 hits were these):
   - run as a command: servers and dev tools invoked by a Dockerfile, compose, CI, pre-commit or a
     script (uvicorn, gunicorn, pytest + plugins, ruff, mypy, eslint, prettier, tsc);
   - named in a config: eslint/prettier/postcss/tailwind/babel/jest/vitest/playwright plugins,
     `@types/*`, Next.js peer deps;
   - loaded by a framework or a URL: DB drivers named in a connection string (asyncpg,
     aiosqlite, psycopg), `python-multipart` (FastAPI forms and uploads);
   - imported under another name: `PyJWT` → `jwt`, `Pillow` → `PIL`, `python-dotenv` → `dotenv`,
     `beautifulsoup4` → `bs4`. Grep the import name, not just the package name.
6. **Only its own tests** -- if the only references are its tests, it is dead code, but removing
   it removes tests too: grade CAUTION, never SAFE.

## 4. Grade: SAFE / CAUTION / DANGER

| Grade | What qualifies | What happens |
|-------|----------------|--------------|
| **SAFE** | Flagged by a tool, every §3 check empty, and one of: unused import or local; unused export of an internal module; unused dependency (§3.5 checked); test helper nothing calls | Deleted automatically in batches (§5) |
| **CAUTION** | Whole files, components, pages' children, API routes, shared utilities; anything with a dynamic-reference shape nearby (§3.2); used only by its own tests (§3.6); vulture confidence below 100% | One batched ask (§6); deleted only if picked |
| **DANGER** | Configs, entry points, framework-convention files (§3.3), public API (`package.json` `exports`/`main`/`bin`, `__all__`, a published package), anything §3.4 found, migrations, auth/RBAC/security code | Never deleted. Listed as a candidate with the reason |

Torn between two grades → the higher one.

## 5. Deletion cadence (SAFE, then picked CAUTION)

1. **Baseline green.** Run the project's full verify set -- backend tests, frontend build,
   type-check, lint (`pytest`, `npm run build`, `npm run type-check`, `npm run lint`, or what
   `package.json`/CI defines; inside the containers if the app runs in Docker). Red baseline →
   stop. Nothing is deleted on a red baseline; hand the failure to `/debug-it`.
2. **One category per batch**, in this order: unused imports/locals → unused dependencies →
   unused exports → unused test helpers → picked CAUTION items. At most ~20 items per batch.
3. **Delete only.** No renames, moves, reformatting, dedupes or "while I'm here" edits in a
   cleanup batch. Removing a dependency also updates its lockfile (`npm install`; rebuild the
   image if the app runs in Docker).
4. **Re-run the verify set immediately.**
   - Green → commit the batch with its log entry (§7):
     `chore(deadcode): remove <N> unused <category>`.
   - Red → `git restore --staged --worktree .` back to the last commit, split the batch in halves
     and retry each half until the item that breaks it is found. That item is regraded CAUTION
     with the failure as its evidence, and the rest of the batch continues. Three failed splits in
     one category → stop that category and report it.
5. Never make a check pass by weakening it: no new lint ignores, no skipped or deleted failing
   tests, no relaxed tool configs. A tool's false positive goes in the log as a candidate with the
   reason, not into an ignore file.

## 6. The CAUTION ask

One ask for the whole run (approval-block.md: consequential; the user picks the specific items,
never a plain yes). AskUserQuestion, `multiSelect: true`, up to 4 questions × 4 options = 16 items,
ranked by strength of evidence; the rest stay candidates. Each option in plain words:

- **label** -- what it is ("Old 'Reports' chart", "Unused 'lodash' package")
- **description** -- the evidence ("no page links to it; nothing loads it by name; knip and
  ts-prune both flag it"), what removing it changes for the user ("nothing you can see"), and the
  undo ("one step to bring it back").

Unpicked items go under `### Kept (user's call)` in the log and are never asked about again.

## 7. Deletion log -- `docs/DELETION_LOG.md`

Created on the first run with a `# Deletion Log` title and one line saying what it is. Each run
appends one section; each batch commit carries its own rows.

```markdown
## <YYYY-MM-DD> -- /deadcode-it

Baseline: <verify set> green at <short sha>. Tools: knip ✓, depcheck ✓, tsc ✓, eslint ✓,
ruff ✓, vulture ✓, deptry ✗ (not run: <reason>).

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
