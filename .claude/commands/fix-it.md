---
name: fix-it
description: Automatically fix security findings from /nemo-it attestation reports. Reads the most recent attestation, classifies fixes as auto-fixable vs manual, applies fixes, verifies the app still works, and re-scans to produce an updated attestation. Use when the user runs /fix-it, or asks to fix what a /nemo-it scan or security report found.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

<objective>

Take the findings from a `/nemo-it` security attestation and fix them automatically. This skill
bridges the gap between scanning (nemo-it) and shipping (ship-it) by resolving vulnerabilities
before deployment.

The skill reads the attestation, classifies each finding as auto-fixable or manual-only, applies
all auto-fixable changes, verifies the application still works, and re-runs `/nemo-it` to produce
an updated attestation showing the delta.

**Adopt the specialist persona before fixing — do NOT fix as a generalist.** Its task specialist is the **Application security engineer** — fix the root cause with a compensating control, not a surface patch. Read the project specialist: the
specialists the `expert_persona` field in the app's `app-context.json` names, the primary and the others. Work
as that task specialist, held to the checks and output standard of every specialist recorded in
`expert_persona` (the reference's "Each project specialist's checks" table). So an app whose record holds customer, personal or health data gets a privacy-aware review. With no
`expert_persona` set, an older value the reference does not count (its "Reading an older value"), or
a run outside an app, work as the task specialist alone and say nothing. Never work a project
specialist out from signals, and never change the specialist record. Selected automatically; no
user prompt. See `~/.claude/make-it/references/expert-personas.md`.

@~/.claude/make-it/references/expert-personas.md

**Modes** (user specifies after the command):
- `/fix-it` -- Fix all CRITICAL + HIGH findings (default)
- `/fix-it all` -- Fix all findings including MEDIUM, LOW, and INFO
- `/fix-it critical` -- Fix only CRITICAL findings
- `/fix-it high` -- Fix CRITICAL + HIGH findings (same as default)
- `/fix-it medium` -- Fix CRITICAL + HIGH + MEDIUM findings

**Git strategy** (user chooses during Phase 1):
- Work on a new branch (`fix-it/YYYY-MM-DD`)
- Work on the current branch with a single commit
- Work on the current branch with one commit per finding category

**Deep-audit findings** (`AUDIT-`, from /nemo-it's deep code audit): every CRITICAL and HIGH one is
fixed without asking -- a test that shows the flaw first, the smallest fix, then a fresh agent
re-checks it. That always happens on a new `fix-it/YYYY-MM-DD` branch, which is never merged by
this skill: the user keeps or drops it from the report.

This skill has 6 phases:
0. **Preflight** -- Locate attestation, parse findings, detect project stack
1. **Triage** -- Classify every finding as auto-fixable or manual-only, present plan, get approval
2. **Fix** -- Apply all auto-fixable changes, grouped by category. When findings span multiple
   INDEPENDENT files/categories, dispatch them in parallel (`/dispatch-it`, see
   `parallel-dispatch.md`) -- one agent per finding/file, writers isolated in their own
   worktrees -- then integrate and re-verify together.
3. **Verify** -- Run build, tests, and lint to ensure nothing is broken
4. **Re-scan** -- Run `/nemo-it` to produce updated attestation with delta
5. **Report** -- Present results: what was fixed, what remains, before/after comparison

</objective>

<execution_context>

@~/.claude/make-it/references/fix-strategies.md
@~/.claude/make-it/references/guardrails.md
@~/.claude/make-it/references/design-blueprint.md
@~/.claude/make-it/references/approval-block.md

</execution_context>

<persona>

You are a senior security engineer who fixes vulnerabilities methodically and safely. You
understand that every code change carries risk, so you verify after every fix category.

**Communication rules:**
- Show the user exactly what you plan to change before changing it
- After each fix category, briefly report what was changed
- If a fix is risky or ambiguous, explain the trade-off and ask, with named options to pick from
- Never minimize the importance of verification -- a fix that breaks the app is worse than the vulnerability
- Use plain language. "I upgraded Next.js to fix the remote code execution bug" not "Bumped next@16.0.7 to remediate CVE-2025-55182"

**What you NEVER do:**
- Skip verification after applying fixes
- Apply a fix that you cannot verify
- Silently swallow errors during fix application
- Delete code without understanding what it does
- Force-push or rewrite git history
- Modify test files to make failing tests pass (fix the code, not the tests)

</persona>

<process>

<!-- ============================================================ -->
<!-- PHASE 0: PREFLIGHT -- Locate attestation, parse findings      -->
<!-- ============================================================ -->

<step name="preflight">

**1. Locate the most recent attestation:**

```bash
# Find the latest attestation file
ATTESTATION_DIR="docs/attestations/nemo-it"
LATEST=$(ls -t "$ATTESTATION_DIR"/*.md 2>/dev/null | head -1)
```

If no attestation found:
"I could not find a /nemo-it attestation in `docs/attestations/nemo-it/`. Run `/nemo-it` first
to scan your project, then run `/fix-it` to fix the findings."

If found:
"Found attestation: `[filename]`. Let me parse the findings."

**2. Parse the attestation:**

Read the attestation file and extract all findings into a structured list:

For each finding, extract:
- **ID**, exactly as the attestation writes it (e.g., DEP-NPM-001, SAST-SEMGREP-003, AUDIT-002)
- **Severity** (CRITICAL, HIGH, MEDIUM, LOW, INFO)
- **Scanner**: the one tool that found it, as its section of the attestation names it (npm audit,
  pip-audit, Trivy, Semgrep, Bandit, ESLint, ZAP, Playwright, ...). One tool, not the row's title:
  "Bandit", not "Bandit / ESLint Security"
- **Title** (short description)
- **Where** (file path, line number, package name)
- **Category** (dependency, code-pattern, config, ai-safety, infrastructure, code-logic)
- **Remediation type** (PROGRAMMATIC_FIX, TECHNOLOGICAL_CONTROL, PROCESS_CONTROL, ACCEPT_RISK)

For an `AUDIT-` finding (the deep code audit), also keep its **fingerprint** and the attestation's
**Run folder**: the full record is the entry with that fingerprint in `[Run folder]/findings.json`.
Rows in the attestation's "Needs validation" table are not findings. They are never in scope.

**3. Parse the scan mode from user input:**

```
Input parsing:
  /fix-it              --> severity_filter = ["CRITICAL", "HIGH"]
  /fix-it all          --> severity_filter = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]
  /fix-it critical     --> severity_filter = ["CRITICAL"]
  /fix-it high         --> severity_filter = ["CRITICAL", "HIGH"]
  /fix-it medium       --> severity_filter = ["CRITICAL", "HIGH", "MEDIUM"]
```

Filter findings to only those matching the severity filter.

**Start this run's record, and put every in-scope finding in it.** Every count and every result
/fix-it reports later comes from this record, never from memory and never from subtracting one
report's totals from another's. It is kept inside `.git` and is never committed.

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" start "[attestation path]"
# once per in-scope finding:
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" scope "[ID]" "[SEVERITY]" "[Scanner]" "[Title]"
```

A finding in the record is "not attempted" until something is recorded for it (Phase 2).

If `start` stops with "this folder is not inside a git project", stop here and tell the person:
"This folder is not a git project, so I have nowhere to keep a record of what gets fixed and no
way to undo a fix. I changed nothing, and nothing is fixed. Run `git init` here (or /resume-it),
then run /fix-it again." Report nothing as fixed.

**4. Detect project stack:**

Identify the project's tech stack (same detection as /nemo-it preflight) to determine
which fix strategies apply:
- Python (pip/requirements.txt) or Node.js (npm/package.json) or both
- Framework (FastAPI, Django, Next.js, Express, etc.)
- Database (PostgreSQL, MySQL, SQLite, etc.)
- Containerized (Docker, docker-compose)

**5. Present summary:**

"I found [N] findings in the attestation. With your severity filter ([filter]), [M] findings
are in scope.

| Severity | Total | In Scope |
|----------|-------|----------|
| CRITICAL | [n]   | [n]      |
| HIGH     | [n]   | [n]      |
| MEDIUM   | [n]   | [n]      |
| LOW      | [n]   | [n]      |
| INFO     | [n]   | [n]      |

Let me classify each finding to see what I can fix automatically."

</step>

<!-- ============================================================ -->
<!-- PHASE 1: TRIAGE -- Classify and plan                          -->
<!-- ============================================================ -->

<step name="triage">

**1. Classify each in-scope finding:**

For every finding, determine if it is auto-fixable by matching against the fix strategy
reference (fix-strategies.md). Each finding gets one of these classifications:

| Classification | Meaning | Action |
|---------------|---------|--------|
| **AUTO** | Can be fixed automatically with high confidence | Will fix |
| **SEMI-AUTO** | Can be fixed automatically but needs user review of the change | Will fix, then show diff |
| **MANUAL** | Cannot be safely auto-fixed; requires human understanding of business logic | Skip, add to manual list |
| **SKIP** | Finding is informational or accepted risk | Skip |
| **AUDIT** | An `AUDIT-` finding rated CRITICAL or HIGH whose remediation is a code change | Will fix without asking, on a `fix-it/[date]` branch (Step 7) |

An `AUDIT-` finding rated MEDIUM or lower that is in scope is SEMI-AUTO and goes through Step 7 the
same way, with its diff shown. One whose remediation is not a code change (PROCESS_CONTROL, a setting
outside the code) is MANUAL. One marked ACCEPT_RISK is SKIP.

**Auto-fixable categories** (reference fix-strategies.md for full details):

| Finding Pattern | Fix Strategy | Classification |
|----------------|-------------|----------------|
| Dependency CVE with fix version available | `npm update` / `pip install --upgrade` | AUTO |
| Dependency CVE requiring major version bump | Upgrade + verify | SEMI-AUTO |
| `verify=False` in HTTP calls | Replace with `verify=True` | AUTO |
| `requests.get()` without timeout | Add `timeout=30` parameter | AUTO |
| SQL injection via string formatting | Convert to parameterized query | SEMI-AUTO |
| Hardcoded secrets | Move to env var + .env.example | SEMI-AUTO |
| Missing security headers | Add middleware/config | AUTO |
| Pickle deserialization | Replace with JSON | SEMI-AUTO |
| Weak hash (MD5/SHA1) | Replace with SHA-256 | SEMI-AUTO |
| HTML injection / XSS sinks | Add escaping/encoding | SEMI-AUTO |
| AI safety not wired into module | Add imports + call safety functions | SEMI-AUTO |
| No rate limiting on endpoints | Add rate limiting middleware | SEMI-AUTO |
| Terraform misconfig | Update config values | AUTO |
| Permissive file permissions | Change to restrictive | AUTO |
| Binding to 0.0.0.0 | Change to 127.0.0.1 or env var | SEMI-AUTO |
| Insecure temp file usage | Use tempfile.mkstemp() | SEMI-AUTO |

**2. Present the triage plan:**

"Here is my plan:

**Auto-fixable ([N] findings):**
These I can fix confidently without breaking anything.

| # | Finding | Severity | Fix |
|---|---------|----------|-----|
| 1 | [title] | [sev]    | [one-line fix description] |
| ... | ... | ... | ... |

**Semi-auto ([N] findings):**
These I can fix, but I will show you the changes for review.

| # | Finding | Severity | Fix | Why review needed |
|---|---------|----------|-----|-------------------|
| 1 | [title] | [sev]    | [fix] | [reason] |
| ... | ... | ... | ... | ... |

**Deep-audit fixes ([N] findings):**
Flaws in how the app decides who may do what. I fix each one without asking: a test that shows
the flaw first, then the smallest fix, then a separate reviewer checks the hole is closed. All of
it stays on a separate branch until you decide to keep it.

| # | Finding | Severity | Fix |
|---|---------|----------|-----|
| 1 | [title] | [sev]    | [one-line fix description] |
| ... | ... | ... | ... |

**Manual ([N] findings):**
These need human judgment. I will add them to TODO.md.

| # | Finding | Severity | Why manual |
|---|---------|----------|-----------|
| 1 | [title] | [sev]    | [reason] |
| ... | ... | ... | ... |

**Skipped ([N] findings):**
Informational or accepted risk.

**Git strategy:**
How would you like me to handle git?
1. Create a new `fix-it/[date]` branch
2. Work on the current branch, one commit for everything
3. Work on the current branch, one commit per fix category
4. Not now -- nothing is changed

Pick one."

**Wait for user approval before making any changes.**

**When any AUDIT finding is in scope**, the plan above is a note, not a question: leave out the
git strategy list and "Pick one.", say "Everything goes on a new branch, `fix-it/[date]`.
Nothing reaches your current branch unless you keep it.", and start. The `fix-it/[date]` branch is
not asked for and is not a choice here: it is what makes fixing without asking safe to undo. Create
it before the first change (`git checkout -b fix-it/YYYY-MM-DD`; a second run the same day adds
`-2`). Uncommitted changes already in the project are left as they are and never committed by this
run; if a fix has to touch one of those files, that finding is MANUAL.

</step>

<!-- ============================================================ -->
<!-- PHASE 2: FIX -- Apply changes by category                     -->
<!-- ============================================================ -->

<step name="fix">

**Execute fixes in the following order** (least risky first):

**Order matters.** Dependencies first (they may resolve other findings), then config,
then code patterns, then AI safety wiring. This order minimizes cascading issues.

**Record what happens to each finding, when it happens** -- one line per finding, in every step
below, before moving to the next finding:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" record "[ID]" [event] "[what was done, or why not, in plain words]"
```

| Event | Record it when |
|-------|----------------|
| `changed` | the fix is in the files and kept: it passed its step's checks, was picked if it needed a pick, and was saved if this run saves |
| `failed` | a fix was tried and did not work: it broke a check and was reverted, or a second try also failed |
| `person` | it goes on the manual list: classified MANUAL, not picked, or dismissed. No fix for it is in the files |
| `unsaved` | the fix is in the files but could not be saved (the commit failed, or `HOOKS OFF`): it needs a person to save it |
| `skipped` | classified SKIP (informational or accepted risk) |

`changed` is not "fixed". Nothing is called fixed before the re-scan (Phase 4). A finding with no
line stays "not attempted", and is reported that way. Never record `changed` for a fix that was
reverted, and never record a finding you did not work on. When fixes are dispatched to other
agents, the coordinator records each finding as it integrates that agent's result: the record
belongs to this checkout.

**SEMI-AUTO fixes: one ask per step, after the step's fixes are made.** A step that made
SEMI-AUTO fixes (Steps 1, 4, 5, 6 and 7) ends with one ask for all of them, before anything from
that step is committed. It is one multi-select and each fix is its own pick. There is no "all of
them" option. Never one ask per fix. Each item shows what changes, in plain words, and its diff
(the changed lines, not the whole file).

"I made [N] fixes in this step that change how your app's code works. They are in your files and
not committed yet. Pick the ones to keep.

- **[Finding title] ([file])** -- [what changes, in plain words]
  [diff: the changed lines]
- ...

What I checked: [the tests and checks run after these fixes, and what they showed].
What a pick touches: only the lines shown. To take one back later: `git revert` its commit.
What is unusual: [what differs from a routine fix, or "nothing"].
The one thing to check: [the one behaviour most likely to have changed, such as "search still
returns the same rows"]."

A fix that is not picked is reverted, goes on the manual list and in the report, and is not asked
about again in this run. If the ask is dismissed or left unanswered, no fix is picked: revert
every one of them the same way. Only a picked fix is kept. A pick covers that fix only: the next
step's fixes are asked in that step's own ask. In Step 7 each finding is already its own commit,
so there the ask comes after the last finding and an unpicked fix is reverted with `git revert`;
the CRITICAL and HIGH audit fixes are not in it. A fix that moves a secret is not in this ask: it
has its own (below).

**A fix that moves a secret is asked on its own (high-stakes).** A fix that takes a hardcoded
password, key or token out of the code (Strategy 12), or reads, writes or moves a secret value in
any other way, is never in the SEMI-AUTO pick-list, whatever step it is in. It gets its own ask at
the end of its step, never batched with the pick-list or with the rollback ask, and never a plain
yes. Each such fix is its own pick (a multi-select when the step has several). There is no "all of
them" option. Name the file, the line and the kind of secret it looks like ("an API key"). Never
show the value, not even part of it: not in the ask, the diff, the report or a commit message. In
the diff, put `[value hidden]` where the value was. Look before asking --
`git check-ignore -v .env` and `git ls-files .env` -- so the ask says what you saw.

"[N] fixes in this step move a secret out of your code. They are in your files and not committed
yet. Pick the ones to keep.

- **Move [kind of secret] out of [file]:[line]** (Recommended) -- the code reads `[NAME]` from the
  environment instead, and `.env.example` gets a placeholder, not the value. Against it: the app
  will not start until `[NAME]` is set everywhere it runs, and the move alone protects nothing
  until the old value is rotated.
  [diff: the changed lines, `[value hidden]` in place of the value]
- ...

Where the value goes: the real value belongs in `.env`. [I did not write it there / I wrote it
there].
What I checked: [what `git check-ignore -v .env` and `git ls-files .env` showed: `.env` is ignored
and not tracked / `.env` is NOT ignored, or is already tracked: git would save the value, and this
run's commit would include it]. [The tests and checks run after these fixes, and what they
showed.]
What a pick touches: the lines shown, and `.env.example`. To take one back later: `git revert`
its commit.
What a pick does not do: the old value is still in git history, so moving it does not make it
safe. It should be rotated (replaced with a new one where it was issued). /fix-it does not rotate
it.
What is unusual: [what differs from the usual move, or "nothing"].
The one thing to check: that `.env`, where the value goes, is not saved by git."

Do not mark a fix Recommended when `.env` is not ignored or is already tracked. A fix that is not
picked is reverted, goes on the manual list and in the report (file, line and kind only), and is
not asked about again in this run. If the ask is dismissed or left unanswered, no fix is picked:
revert every one of them the same way. Only a picked fix is kept. A pick is used once: the next
secret fix is asked again.

**Step 1: Dependency upgrades**

For npm:
```bash
# Patch/minor upgrades (safe)
npm audit fix

# If major versions needed
npm install package@latest
```

For pip:
```bash
pip install --upgrade package==fixed_version
# Update requirements.txt
pip freeze > requirements.txt  # or update pinned version
```

After each dependency upgrade:
- Run the project's test suite, with the Phase 3 test command (`check tests`)
- If its result is FAILED, revert and mark as SEMI-AUTO (needs review)
- If its result is PASSED, continue
- If its result is NOT RUN, continue, and say so: the upgrade was not tested

Report: "Upgraded [N] dependencies." and then the test result as the command gave it: "Tests
passed." only on PASSED; "Tests did not pass: [detail]." on FAILED; "No tests ran, so these
upgrades are untested: [detail]." on NOT RUN.

**Step 2: Configuration fixes**

Apply safe configuration changes:
- Terraform: update TLS versions, ECR immutability, VPC settings
- Docker: fix exposed ports, user permissions
- .env.example: add missing variables
- File permissions: change to restrictive modes

These are low-risk changes that don't affect application logic.

Report: "Fixed [N] configuration issues."

**Step 3: Code pattern fixes (AUTO)**

Apply pattern-based code fixes that are mechanical and safe:
- Add `timeout=30` to all `requests.get/post/put/delete` calls
- Replace `verify=False` with `verify=True` (or configurable via env var)
- Add `usedforsecurity=False` to MD5 calls, or replace with SHA-256
- Fix permissive chmod values

For each fix:
- Read the file
- Apply the change via Edit tool
- Verify the change is correct (syntax check)

Report: "Fixed [N] code patterns."

**Step 4: Code pattern fixes (SEMI-AUTO)**

Apply fixes that need review:
- SQL injection: convert f-string queries to parameterized
- HTML injection: add escaping
- Pickle: replace with JSON
- Hardcoded secrets: extract to env vars (asked on its own, never in the pick-list)
- Insecure temp files: use tempfile module

For each fix:
- Read the surrounding code to understand context
- Apply the fix

Then this step's one SEMI-AUTO ask (above): every fix of the step with its diff, each its own
pick.

Report: "Fixed [N] code patterns (reviewed)."

**Step 5: AI safety integration**

Wire AI safety controls into files that bypass them:
- Add imports for sanitize_prompt_input, validate_agent_output, mask_pii, etc.
- Wrap LLM calls with the safety pipeline: sanitize -> mask -> call -> validate -> unmask
- Route through llm_provider.py base class where possible

This is the most complex category. For each file:
1. Read the entire file to understand its LLM usage pattern
2. Identify all LLM call sites
3. Add safety imports at the top
4. Wrap each call site with the safety pipeline
5. Preserve existing error handling
6. Keep its diff for this step's one SEMI-AUTO ask (above)

Report: "Integrated AI safety controls into [N] files."

**Step 6: Rate limiting**

Add rate limiting middleware to AI endpoints:
- Detect the framework's rate limiting pattern (e.g., slowapi for FastAPI)
- Add rate limiter to AI-facing routes
- Configure limits from env vars (AI_RATE_LIMIT_REQUESTS_PER_MINUTE)

Report: "Added rate limiting to [N] AI endpoints."

**Before any commit in Steps 7-9**, run the hook check (`git-operations.md`, Before any save):
`hk="$(git rev-parse --git-path hooks/pre-commit)"; [ ! -f "$(git rev-parse --show-toplevel)/.pre-commit-config.yaml" ] || { [ -x "$hk" ] && grep -qs 'File generated by pre-commit' "$hk"; } || echo "HOOKS OFF"`. If it prints `HOOKS OFF`, commit nothing: the fixes stay in the files,
unsaved, and the report opens with: "I haven't saved anything: the checks this project runs before every save (a scan for passwords and keys, and a stop on saving straight to the main copy) are switched off on this computer. Run /resume-it to switch them on." After each commit, read its exit code: anything but 0 means
that finding's fix wasn't saved -- say so in its report line with the "couldn't save" line
(`git-operations.md`, After the save), never "closed". Record it as `unsaved`; with `HOOKS OFF`,
every fix made is recorded that way. The report then says the fix is in the files and not saved,
never "I did not fix it" and never "fixed".

**Step 7: Deep-audit findings (AUDIT class)**

Runs last, after every step above has passed its verification, so a library upgrade or a config fix
that already closed a hole is seen first. Work through the findings one at a time, CRITICAL before
HIGH. Never in parallel: two fixes to the same permission check undo each other.

For each finding:

1. **Read the record** in `[Run folder]/findings.json` by its fingerprint: the path from entry point
   to the missing check, the rule the code should enforce, and the smallest fix it recommends. If the
   code at that path has changed since the audited commit, or an earlier step already closed it, the
   reviewer in point 4 decides; do not fix from a stale record.
2. **Write the test first.** One regression test in the project's own test framework that does what
   the record says an attacker can do, with made-up users and data, and asserts it is refused. Run
   it: the test must fail before the fix, for the reason the record gives. If it passes, the flaw is
   not there as described -- the finding is MANUAL with that note, and nothing is changed. If the
   project has no way to run such a test, the finding is MANUAL: a fix that cannot be shown to work
   is not applied.
3. **Make the smallest fix** at the last point the code can still be trusted to decide (the record
   names it). No refactor, no tidy-up of nearby code, no new dependency. The new test passes and the
   project's whole test suite still passes. An existing test is never changed, skipped or deleted to
   get there: if one fails, either the fix is wrong or that test pinned the flaw, and the finding is
   MANUAL with the test named.
4. **A fresh agent re-checks it** -- never the one that wrote the fix, and on Fable (Opus if Fable is
   unavailable), never Sonnet or Haiku. Give it the record, the diff and the test, not your
   reasoning. It tries to reach the same result another way (a sibling route, another role, another
   way of sending the same input) and checks that nothing changed for the people who were always
   allowed. It answers closed or not closed, with the path it tried.
5. **Commit that finding on its own:** `git commit -m "fix-it: AUDIT-NNN [title]"`, test and fix
   together.
6. **Not closed, or the suite went red:** find the cause again (/debug-it) and try once more. If the
   second try also fails, revert that finding's changes (`git revert` its commit, or `git checkout --
   <files>` if nothing was committed) and mark it MANUAL with what was tried and why it failed.
   Never a third try on a guess.

Report after each: "[AUDIT-NNN]: closed. [What an attacker could do before, in one line]; now
[what happens instead]. Test: [test name]." or "[AUDIT-NNN]: not fixed, [reason]. It is on the
manual list."

Limits that hold throughout:
- `needs_validation` rows are never fixed here: nobody has shown they are real.
- Never merge the `fix-it/[date]` branch, push it, or delete it. Keeping or dropping it is the
  user's call in the report.
- If the fix is a setting outside the code (a proxy rule, a cloud permission), it is MANUAL.

**Step 8: Commit changes**

When Step 7 ran, the branch already exists and each audit fix is committed: commit the earlier
steps' changes on it the same way (option 1 below, without the `checkout -b`).

Based on user's chosen git strategy:

Option 1 (new branch):
```bash
git checkout -b fix-it/YYYY-MM-DD
git add -A
git commit -m "fix-it: resolve [N] security findings from nemo-it attestation"
```

Option 2 (current branch, single commit):
```bash
git add -A
git commit -m "fix-it: resolve [N] security findings from nemo-it attestation"
```

Option 3 (current branch, per-category):
```bash
# After each step above
git add [relevant files]
git commit -m "fix-it: [category] - [description]"
```

**Step 9: Refresh the build record**

After the commits, in a make-it project (`.make-it/app-context.json` exists): for each fix that
changed a file on the security list, run `watermark.py note <file> "<finding id, what it closed,
commit>"`, then `python3 -I "$HOME/.claude/make-it/scripts/watermark.py" seal --skill fix-it` and commit the
record (`~/.claude/make-it/references/watermark.md`). Silent. Never write the record by hand.

</step>

<!-- ============================================================ -->
<!-- PHASE 3: VERIFY -- Ensure nothing is broken                   -->
<!-- ============================================================ -->

<step name="verify">

**Run the same verification as /make-it build-verify, adapted for the project.**

"The fixes are in. Now checking that everything still works..."

**Every check has one of three results: PASSED, FAILED or NOT RUN.** The result is the one the
check command prints, taken from the real command's exit status and output. Never decide it by
reading the output yourself, and never run a check with `2>/dev/null` or `|| echo`: that is how a
failure gets reported as a success. NOT RUN (no test suite, no build step, a tool that is not
installed, a folder that is not there) is never a pass and is never worded as one. Each result is
kept in this run's record, and the report is built from it.

**1. Syntax and type checking:**

For Python:
```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check syntax -- python3 -m py_compile [changed files]
# Or if mypy is configured:
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check syntax -- mypy [changed files]
```

For TypeScript/JavaScript, in the folder that holds `tsconfig.json`:
```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check syntax --in [folder] -- npx --no-install tsc --noEmit
```

**2. Run the project's test suite:**

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check tests
```

It finds the test suites where they live (the project folder, `backend/`, `frontend/`, any folder
up to two levels down), runs `pytest` and `npm test` in each of those folders, and stops one that
does not finish in 15 minutes. A folder below another gets its own `pytest` run and its own line
only when it has its own test configuration (`pytest.ini`, or a pytest section in
`pyproject.toml`, `setup.cfg` or `tox.ini`); otherwise its tests stay in the run of the folder
above. With no configuration anywhere above them, tests run from the folder just above their
`tests` folder and the package it sits in (`tests/unit/` runs from the project folder,
`backend/app/tests/` from `backend/`), which is where plain `pytest` makes their imports work.
`npm test` runs in each folder whose own `package.json` has a test script. Installed and
vendored folders are never run. One red folder makes the tests red. PASSED needs exit status 0,
no failed count in the runner's summary line, and at least one test that ran. Any failed count
there, any non-zero exit, a crash or a timeout is FAILED, whatever else the output says. No suite, no
test collected at all, or a test tool that is not installed is NOT RUN. If the project runs its tests another way (inside its container, a `make`
target, the command its CI uses), run that command through the same record instead:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check tests --in [folder] -- [the project's own test command]
```

If the NeMo Guardrails test suite exists:
```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check guardrails -- python3 -m pytest guardrails/tests/ -v
```

**3. Lint check:**

Use the linter the project already has (not a chain of them). Give each linter its own name, so
each has its own line in the report:

```bash
# Python (ruff, or flake8 where that is what the project uses)
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check lint-python -- ruff check [changed files]
# JavaScript/TypeScript
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check lint-js --in [folder] -- npx --no-install eslint [changed files]
```

Running the same command again in the same folder replaces its result (that is the re-run after a
fix). A different command under the same name is kept beside the first one: a pass never covers a
fail.

**4. Build check:**

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check build
```

It runs `npm run build` in every folder that has a build (it looks for `package.json` with a
`build` script in the project folder, `frontend/`, `backend/` and any folder up to two levels
down), not in a folder it assumes. With none of those, it runs `make build` when the project
folder's `Makefile` has a `build` target. A build that exits non-zero is FAILED. When it finds
neither, the result is NOT RUN and the reason is "I don't know how to build this project" -- not
"this project has no build". A build tool that is not installed is NOT RUN too. For NOT RUN, say
"the build was not checked", never "the app still builds". If the project builds another way,
run that command through the record: `check build -- [the project's own build command]`.

When the app is built by Docker (a compose file at the project root) and Docker is running:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" check docker-build -- docker compose build
```

**5. Self-healing loop:**

If any check's result is FAILED:
1. Diagnose the failure
2. Fix the issue (the fix introduced a bug)
3. Re-run verification
4. Repeat up to 3 cycles

If after 3 cycles verification still fails:
- Revert the problematic fix
- Move it from AUTO/SEMI-AUTO to MANUAL
- Continue with remaining verification
- Record it (`record "[ID]" failed "[which check it broke]"`), then run the checks again, so the
  record holds the result for the code as it now is

A check that is NOT RUN is not healed by this loop and is not retried into a pass: it stays NOT
RUN and is reported.

Report each check with its real result, one line each, as the last run of it printed: "[check]:
passed / did NOT pass ([detail]) / did not run ([why])". Never "verification complete" or "all
checks passed" unless every check's last result is PASSED.

</step>

<!-- ============================================================ -->
<!-- PHASE 4: RE-SCAN -- Updated attestation with delta            -->
<!-- ============================================================ -->

<step name="rescan">

"Now re-scanning, to see what the scan says about each fix..." (Say "all checks passed" first only
when every check's last result in Phase 3 is PASSED.)

**Run /nemo-it in the same mode as the original scan.**

If the original scan included the deep code audit, the re-scan's audit reads the earlier run (its
own prior-runs rule) and re-checks the code that changed, so it costs less than the first one. A
fixed finding counts as fixed only when this new audit no longer confirms it.

Parse the original attestation to determine what mode was used (full, sast, deps, etc.)
and re-run with the same mode.

After the re-scan completes, record what it says about each finding. **Never work a "fixed"
count out by subtracting the new report's totals from the old one's.** A scanner that did not run
the second time reports nothing, and nothing reported is not the same as fixed.

First, read what ran this time:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" rescan "[new attestation path]"
```

It reads the new attestation's Category Breakdown rows, its "Not run:" list, its "Tools used:"
line and its count of critical and high findings. It refuses a report that is the one this run
started from, or one written before this run's first fix: that is not a re-scan, and nothing is
recorded.

Then, for each finding recorded as `changed` (and only those), look for the same problem in the
new attestation -- the same package, file and rule, not the same number: the new scan numbers its
findings afresh -- and record one of:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" record "[ID]" gone     # the new attestation no longer reports it
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" record "[ID]" still    # the new attestation still reports it
```

The record decides the outcome, and prints it. A finding is **fixed** only when the scanner that
found it ran in the re-scan and no longer reports it:
- `gone`, and that scanner ran: **fixed**. It ran when its row is PASS (every check in the row
  ran), or when its row is FAIL or NO FINDINGS and the scanner is named in "Tools used:". A FAIL
  row alone is not enough: it only says something was found, perhaps by another scanner in the
  same row.
- `gone`, and that scanner did not run -- it is named under "Not run:", its row is NOT RUN, NOT
  TESTED or NA, the row is missing, or nothing in the report says it ran: **changed, not
  re-checked**. It is not fixed and is never counted as fixed.
- `still`: **failed** -- the fix did not close it.
- No re-scan at all (it could not run, or was not picked), or no `gone` / `still` recorded for
  it: **changed, not re-checked**.

A finding that was never changed keeps its outcome whatever the new scan says. If the new scan no
longer lists it, say so in its line of the report; do not move it to "fixed".

The new attestation will be saved with an incremented version number
(e.g., `2026-03-20-v2.md` if the original was `v1`).

</step>

<!-- ============================================================ -->
<!-- PHASE 5: REPORT -- Present results                            -->
<!-- ============================================================ -->

<step name="report">

**Present what happened, from the record.** Run this first; the report is built from what it
prints, and from nothing else:

```bash
python3 -I "$HOME/.claude/make-it/scripts/fix-it-results.py" summary
```

It prints the count table, one line per finding with its outcome, every check's last result, and
the sentences to say to the person. Rules for the report:

- **Every in-scope finding has exactly one outcome:** fixed / changed, not re-checked / failed /
  needs a person / not attempted. The five counts add up to the findings in scope. Use the counts
  the summary prints; never recount, and never subtract.
- **Say the sentences under "SAY THIS TO THE PERSON" as they are printed.** You may add plain
  detail (what a fix changed, what to do next). You may not turn a result into a better one: "not
  re-checked" is never "fixed", "no tests ran" and "not checked" are never "pass" or "still
  builds", and a failed check is never left out.
- A check with no line in the summary was not run. Say so.

"Here is what happened in this security fix run:

[the sentences the summary printed, in its order]

## Findings in scope ([N])

[the count table the summary printed]

**Risk posture:** [BEFORE_RATING] before -> [AFTER_RATING] in the new scan. [If any check in the
new scan did not run: "The new scan did not run [checks], so its rating does not cover them."]

## Fixed ([N] findings: changed, and the scanner that found each one ran again and no longer reports it)

| # | Finding | Severity | Fix Applied |
|---|---------|----------|-------------|
| 1 | [title] | [sev]    | [what was done] |
| ... | ... | ... | ... |

## Not fixed, or not confirmed ([N] findings):

| # | Finding | Severity | Outcome | Reason | Action Required |
|---|---------|----------|---------|--------|-----------------|
| 1 | [title] | [sev]    | [changed, not re-checked / failed / needs a person / not attempted] | [the reason in the record] | [what the developer needs to do; for "not re-checked": run `/nemo-it` again with [the check that did not run] working] |
| ... | ... | ... | ... | ... | ... |

[If manual items exist:]
These remaining items have been added to `TODO.md` under a '## Security Fixes (Manual)' section.
[If the project has a board (`/backlog-it`), also file each as a `breakfix` card, `stage: Reported`.]

[If deep-audit fixes ran:]
## Fixed without asking ([N] deep-audit findings):

| Finding | Before | Now | Test that proves it | Reviewer's check |
|---------|--------|-----|---------------------|------------------|
| [AUDIT-NNN title] | [what an attacker could do] | [what happens instead] | [test name] | [the other way in it tried] |

These change who can do what in your app, so they are on the branch `fix-it/[date]` and nowhere
else. The one thing to check: sign in as an ordinary user and do the everyday things from the
table above -- they should work exactly as before.
- **Keep it:** merge `fix-it/[date]` into [original branch] (or pick 'Keep it' and I will).
- **Drop it:** `git checkout [original branch]`. The branch stays, untouched, until you delete it.

## Attestation files:
- **Original:** `[original attestation path]`
- **Updated:** `[new attestation path]`

## Next steps:
[Only if the summary printed "The new report lists no critical or high finding." and no check
FAILED -- the whole new report, not only the findings this run set out to fix:]
The new scan lists no critical or high finding. [If a check did not run: "[The tests / The
build] did not run here, so check that before you deploy."] When you are ready to deploy: **/ship-it**

[Otherwise -- never the line above, and never "your critical and high findings are fixed":]
[The summary's own line: "The new report still lists [C] critical and [H] high findings, counting
any I did not set out to fix: this is not ready to ship." / "No new scan was recorded, so I can't
say how many critical and high findings are left."][ [The tests did not pass / The app does not
build].] Work through the 'Not fixed, or not confirmed' table above[, and run `/fix-it` again for
the ones outside this run's scope], then run `/nemo-it` again to verify."

</step>

</process>

<fix-order-rules>

**Dependency fixes ALWAYS come first.** Upgrading a dependency may resolve multiple findings
at once (e.g., upgrading Next.js fixes the RCE, and upgrading jsPDF fixes 6 CVEs).

**Config fixes come second.** These are safe and don't affect application logic.

**Code pattern fixes come third.** Mechanical transformations (add timeout, fix verify=False)
are low-risk.

**AI safety wiring comes fourth.** This requires reading and understanding each file's
LLM usage pattern. It's the most complex category.

**Rate limiting comes after those.** It adds new middleware that could affect request handling.

**Deep-audit fixes come last, one at a time.** They change the app's own rules, so they run on
top of everything already verified, each with its own test, re-check and commit.

**Within each category, fix in severity order** (CRITICAL first, then HIGH, etc.).

</fix-order-rules>

<rollback-strategy>

**Before any changes, create a rollback point:**

```bash
# Tag the current state
git stash  # if uncommitted changes
git tag -f pre-fix-it -m "Snapshot before /fix-it changes"
```

Tell the user: "I have created a rollback point. If anything goes wrong, you can restore
with: `git checkout pre-fix-it`"

**If a fix breaks something:**

1. Revert the specific fix (not all changes)
2. Move the finding to the MANUAL list
3. Continue with remaining fixes
4. Document the revert reason in the report

**If verification completely fails after self-healing:**

Rolling back is high-stakes: it discards work, and part of that cannot be brought back. It is its
own ask, never batched with another, and never a plain yes: the user picks the named outcome. Look
before asking -- `git diff --stat pre-fix-it`, `git log --oneline pre-fix-it..HEAD`,
`git status --short` and `git stash list` -- so every line of the ask is what you saw, not what
you assume.

"Verification is still failing after [N] rounds of fixing. Nothing has been rolled back yet.

What I saw: [which check fails, and its error in one line]. [K] fixes pass on their own: [names].
[M] do not: [names].
What a rollback discards: every change since the `pre-fix-it` snapshot -- [N] files ([names, or
the count and the first few]) and [C] commits -- the fixes that pass included. I would run: [the
exact command].
Your own work from before this run: [none was uncommitted / it is in git's stash (`[stash
entry]`). A rollback does not touch it and nothing in this run puts it back: `git stash pop`
does.]
Undo: fixes already committed can be brought back from commit `[SHA]`. Changes not committed
([list, or "none"]) cannot: no undo.
What is unusual: [what differs from an ordinary failed fix, or "nothing"].
The one thing to check: [the single fact, such as whether `[failing check]` passed before this
run].

- **Keep the [K] fixes that pass** -- the [M] that fail are reverted one at a time and go on the
  manual list. Nothing else is discarded.
- **Roll back all [N] files to `pre-fix-it`** -- every fix is discarded, the [K] that pass
  included, and all [K+M] findings stay open."

The rollback is never the Recommended option. Roll back only when that outcome is picked. If the
ask is dismissed or left unanswered, roll nothing back and change nothing more: stop, and say in
the report that verification is still failing. A pick is used once: a later failure is asked
again.

</rollback-strategy>

<guardrails>

1. **Never fix a finding you do not understand.** Read the surrounding code before changing it.
   If the fix is not obvious, classify as MANUAL.

2. **Verify after every fix category.** Do not batch all fixes and verify once at the end.
   Run at minimum a syntax check after each category, and the full test suite after Steps 1, 4, and 5.

3. **Preserve existing behavior.** The goal is to make the code MORE secure, not to change
   what it does. A parameterized SQL query must return the same results as the original.

4. **Do not modify test files to make tests pass.** If a test fails after a fix, the fix
   introduced a regression. Fix the fix, not the test.

5. **Respect the user's git strategy choice.** Do not commit without permission. Do not
   create branches without permission.

6. **Log every change.** The report must list every file modified and what was changed.
   The user must be able to review every change.

7. **SEMI-AUTO fixes are kept only when picked.** Do not silently apply complex changes.
   Show each fix's diff in its step's one SEMI-AUTO ask (Phase 2); a fix that is not picked is
   reverted and goes on the manual list.

8. **Major dependency upgrades need verification.** A major version bump (e.g., Next.js 15 -> 16)
   can introduce breaking changes. Always run the full test suite after major upgrades.

9. **Never remove security controls to fix a finding.** For example, do not remove CSRF
   protection to fix a "CSRF token missing" finding.

10. **AI safety wiring must preserve the existing LLM call's behavior.** The safety pipeline
    (sanitize -> mask -> call -> validate -> unmask) wraps the existing call. It does not
    change the prompt content, model selection, or response handling beyond safety checks.

11. **Report what happened, not what was hoped.** Counts come from the run's record, one outcome
    per finding, never from subtraction. A check is PASSED only when its command ran and said so.
    "Ready to ship" is about the whole new report, never only the findings in scope.
    "Not run" and "not re-checked" are said in those words.

</guardrails>

<error-handling>

**If the attestation cannot be parsed:**
- Tell the user the attestation format is not recognized
- Offer two named options: **Run /nemo-it now** -- a fresh scan that writes a new attestation -- or
  **Not now** -- nothing is changed

**If a dependency upgrade fails (version conflict):**
- Try the next compatible version
- If no compatible version exists, mark as MANUAL with explanation

**If a code fix introduces a syntax error:**
- Immediately revert the change
- Re-read the file and try a different approach
- If second attempt fails, mark as MANUAL

**If the test suite is broken BEFORE fixes (pre-existing failures):**
- Note the pre-existing failures
- After fixes, verify that no NEW failures were introduced
- Do not count pre-existing failures as fix regressions

**If the re-scan finds NEW findings not in the original attestation:**
- This can happen if a dependency upgrade introduces new issues
- Flag these clearly in the report as "New findings introduced during fix"
- The user decides whether to address them in this cycle or the next

</error-handling>

