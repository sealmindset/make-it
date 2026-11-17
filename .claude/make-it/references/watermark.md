# The Build Record and Its Check (the make-it watermark)

How an organization knows that code went through make-it's guardrails and security checks,
without asking the builder to do anything. Three parts: the guardrails are always on (managed
settings), make-it writes down what it did (the build record), and GitHub checks the code itself
(the proof). Checks WM01-WM04 in `build-standards.md`.

**The idea in one line:** nothing on a builder's computer can be trusted as proof, so the record
written there is only a claim, and the check that counts runs in GitHub where builders can't edit it.

## The seal (works anywhere, with nothing but the project and git)

Two tiers. **The seal** is everything a project carries by itself: no account, no service, no
special plan. **The organization's check** (sections 2 to 4) is the stronger tier for a company
that has GitHub Enterprise Cloud. The seal works today, for any project.

**What it is.** When a make-it skill has finished and checked its work, it seals the project:

```bash
python3 -I "$HOME/.claude/make-it/scripts/watermark.py" seal --skill <skill> [--results <file>]
```

That fingerprints the project's code and adds one entry to `.make-it/ledger/`, chained to the
entry before it. Code that no longer matches a seal was changed outside make-it.

| It writes | What it is |
|---|---|
| `.make-it/ledger/<n>-<hash>.json` | One entry per make-it run: the skill, the make-it release, the date, the code's fingerprint, the security files' state, the check results, and the hash of the entry before it. One file per entry, so two branches never clash. |
| `.make-it/manifest.json` | The build record (section 1). |
| `.make-it/sealed-files.txt` | The file list behind the latest fingerprint, so a failed check can name what changed. |
| `MAKE-IT.md` | The seal for a person: built with which make-it, every run, the security files' state, how to check it. |
| `backend/make-it-stamp.json` | A small copy the running app reads. |

**What counts.** Every file git tracks or would add, except Markdown, `.make-it/` and the stamp.
Docs can change freely. Code cannot change without breaking the seal. A file counts by its content
and whether it is executable. A link counts by what it points at, even a file the seal otherwise
skips; a link that points outside the project fails the check and is never read. A submodule counts
by the commit it points at, and a nested repository by its files. Commit everything before pushing:
a new file that was sealed but not committed makes the next clean checkout fail.

**What it sets up.** The first seal adds four lines to the project's `.gitattributes`: `* -text`,
so git never rewrites line endings (that would change every fingerprint on some machines), and
`merge=union` for the three files the seal regenerates, so two sealed branches merge without a
conflict in them.

**Who seals.** Every make-it skill that changes a project, at its end, after its own checks:
/make-it, /retrofit-it, /resume-it, /fix-it, /deadcode-it, /argo-it, and /try-it when its fix
cycle changed something. /wrap-it never seals: it saves work, it does not check it. The hook in
section 4 keeps the record current but never seals, or a hand edit made in a session would be
sealed by the next turn.

**What the check adds** (`watermark.py verify`, the same command everywhere):

| It checks | When it doesn't hold |
|---|---|
| The code's fingerprint matches a seal | **fail**: "N file(s) changed outside make-it since /skill sealed it on date", naming them, and "Run /resume-it in this project, then push again." |
| The history behind that seal is whole | **fail**: an entry was removed or edited |
| The project has been sealed at all | **fail** |
| The seal and the record name the same make-it release | **fail** |

/resume-it is the way back: it rechecks what changed (its catch-up and its security step), then
seals. Two sealed branches merged together are new content, so they fail until sealed; the new
entry then joins both histories. A damaged history is never sealed over silently: `seal` refuses,
and only the user can go on, with `seal --restart "<why>"`, which `MAKE-IT.md` shows from then on.

**Where each reader sees it**
- **A person:** `MAKE-IT.md` at the project's root.
- **GitHub Actions:** the `watermark` job in the scaffold's `quality-gate.yml` checks out make-it
  at the record's release tag and runs `verify`. A fail fails the job. A changed security file that
  make-it sealed passes with a warning.
- **Jenkins, GitLab CI, Azure DevOps, any other CI system:** one script the scaffold ships,
  `scripts/watermark-check.sh`, does the same in one line (it needs bash, git, python3 and a way to
  reach the make-it repository; `MAKE_IT_REPO_URL` points it at a mirror). In a `Jenkinsfile`:

  ```groovy
  stage('make-it watermark') { steps { sh 'bash scripts/watermark-check.sh' } }
  ```

  Build the pull request's own commit, not a merge with the base branch (in Jenkins: discover pull
  requests by "the current pull request revision").
- **The running app:** `GET /api/admin/about` (admin settings permission) rehashes its own
  security files inside the container and compares them with the stamp. The admin settings page
  shows it as "About this app". Admins only: it is never public.

**Only the newest seal counts.** Code rolled back to an older sealed state fails until it is sealed
again. The CI job refuses a make-it release older than 1.60.0, the first that checks the seal, and
checks the pull request's own commit, not GitHub's trial merge with the base branch.

**The limit.** The seal attests. It does not prove. A person who runs `watermark.py seal` by hand
gets a valid seal, and a project's owner can remove the job from their own CI. Deleting the newest
history entries and putting the code back to match an older one also passes: nothing outside the
project remembers the newer seal. The seal reliably
shows code that never went near make-it, hand edits, and anything changed since make-it last ran.
Resisting someone who sets out to fake it is what the organization's check is for.

## 1. The build record: a claim, not proof

`.make-it/manifest.json`, committed with the code. Written by one script and nothing else:

```bash
python3 -I "$HOME/.claude/make-it/scripts/watermark.py" write [--results <file>]
```

It holds:
- `framework` -- the make-it release installed when the record was written (version and the
  digest of that release's `CONTENT_MANIFEST`). After a make-it update that changed a security
  file, the project's older copy shows as `changed` until it is brought up to date or reviewed.
- `project` -- type, tiers, scaffold.
- `security_files` -- for each file on the scaffold's list (`~/.claude/make-it/watermark/
  protected-<scaffold>.txt`): its hash, the hash the release shipped, and `match`, `changed` or
  `missing`.
- `security_results` -- what the build's security step did, passed with `--results` as a small
  JSON object: checks run, whether the deep code audit ran (or why not), how many findings were
  fixed and how many are open. Counts and states only: short lowercase keys with a number, a
  true/false or a short text. Anything else in the file is dropped.

It never holds a secret, file contents, or a time: the same code always gives the same bytes, so
rewriting it does not churn the project's history.

**Rules**
- **Written silently.** The user is asked nothing and told nothing about it. If the script cannot
  run, the build goes on; say so only in the run's own report.
- **Only the script writes it.** Never edit or write `.make-it/manifest.json` by hand, and never
  from any other tool. A hand-made record gains nothing: the check does not believe it.
- **When:** at the end of every run that changes code -- /make-it (before its state file),
  /retrofit-it, /resume-it (before it saves state and before the ship hand-off), /fix-it (after
  its commits). Commit it with the change it describes.
- **A fix in a security file is noted.** When a framework fix (a deep-audit fix, Strategy 13)
  changes a file on the list, record why, so the reviewer sees it:
  `watermark.py note <file> "<finding id, what it closed, commit>"`.
- **Don't edit security files for ordinary work.** New permissions go in a new migration and new
  routes in new files. The list holds only files a build has no reason to change.

## 2. The check: the proof

```bash
python3 -I watermark.py verify --app <project> [--framework <make-it>/.claude/make-it] [--base-ref <commit id>] [--allow-unlisted] [--json]
```

It recomputes everything from the code and never trusts the record's hashes or its claims.
Everything in the project is treated as hostile: files are read as data, only as plain files up to
1 MB, never through a link, and Python is parsed, never run or text-matched.

| It checks | Result when it doesn't hold |
|---|---|
| A readable record exists | **fail**: "Run /resume-it in this project, then push again." |
| The record's release is the one being checked against | **fail** |
| Every security file exists as a plain file | **fail** |
| Every security file is byte-for-byte what the release shipped | **security review** (unless the same content is already in the base commit: then accepted) |
| The project holds make-it's security files at all | **security review**: nothing could be checked (`--allow-unlisted` turns this into a pass with a note, for project types that have no list yet) |
| The tables the release's first migration creates are created by a migration, and none is dropped | **fail** |
| Every route under `backend/` carries its own check, written exactly as `Depends(require_permission(...))`, in its parameters or its decorator's `dependencies=[...]`, with both names imported plainly at the top of the file | **fail** |
| Nothing under `backend/` defines, replaces or re-imports `require_permission` or `Depends`, overrides a dependency outside the tests, imports the tests into the app, or registers a route any way but a decorator | **fail** |
| Every Python file under `backend/` is a plain file that parses; no folder is skipped, and a linked folder or a compiled file with no source counts against it | **fail** |
| The backend holds only plain route code. Anything this check cannot be sure about -- code built while running (`exec`, `eval`, `globals()`, `importlib`), `import *`, routes or request filters added without a decorator, a router used any other way, a sign-in module taken as an object | **security review** |

Exit codes: `0` pass, `1` fail, `3` security review needed. A record that claims "no scaffold"
does not switch the file check off: the scaffold is found from the code. The code rules are
measured against the release's own scaffold and counted, so what the release itself does (its
health routes, its one middleware) never fails, and one more of the same does. `--base-ref` takes a full 40-character commit id only: a branch or
tag name could belong to the pull request.

**Security review, not a block.** A changed security file is often legitimate -- make-it's own
audit fixes permission checks. So the pull request is not failed; it needs an approval from the
organization's security reviewers. Once that content is merged, it is accepted and not asked about
again.

**What it proves, and what it doesn't.** A pass proves that the code under `backend/` has
make-it's released security files unchanged and keeps the rules above. It does not prove:
- that every line was written through make-it. Nothing can, on a computer the builder controls;
- that the deployed container runs that `backend/` folder. A second copy of the app elsewhere in
  the repository is not looked at. `backend/Dockerfile` and `backend/entrypoint.sh` are on the
  security list, but `docker-compose.yml` and the deploy settings are not, because the build fills
  them in. Checking what is deployed belongs to the deploy step;
- anything about files the build customises (`main.py`, `config.py`, the first migration's seed
  data): they cannot be hashed. The code rules still apply to them;
- anything for project types other than the FastAPI + Next.js scaffold in v1: those need review
  or a named exception.

**Only plain code passes on its own.** Two independent adversarial reviews (2026-11-16) each got a
clean pass with an unprotected route, the second time against a check that listed known-bad
shapes. So the rule is the other way round: ordinary route code passes, and anything unusual needs
a person. `scripts/test-watermark.py` holds one test per bypass those reviews found, and one that
ordinary generated code passes without review.

This is still reading code, and Python can always be written another way. Known gap: a route
registered through an object imported from another file and passed as a value (for example
`map(app.get("/x"), [f])`). The answer to that class is the next phase, not more patterns: the
GitHub check starts the app, asks it for its real routes, and calls each one without signing in.
Until that ships, treat a pass as "nothing wrong was found", not as proof against someone acting
on purpose.

## 3. In GitHub (set up once by the organization)

The check runs from an organization-owned repository (`make-it-verify`), required on every
repository by an organization ruleset, so no project can edit or skip it. On a pull request it:

1. checks out make-it at the release the record names (and refuses a release that is not on its
   allowed list);
2. runs `watermark.py verify --base-ref <the base commit's id>` from that checkout, plus the
   hostile-code check, a secret scan and a dependency audit;
3. on `3`, requires the security reviewers' approval;
4. on a pass on the default branch, issues a GitHub artifact attestation for the commit's file
   list, signed as that workflow. Deploy workflows verify it first: no attestation, no deploy.

Needs GitHub Enterprise Cloud: the required-workflow rule and attestations on private
repositories are not in the Team plan (checked against GitHub's docs, 2026-11-16). On other plans
the same workflow can run as an ordinary required status check, without the attestation.

**The same gate in Jenkins.** An organization whose builds run in Jenkins holds the check in a
*global* shared library that only Jenkins administrators can change (`make-it-verify` is laid out
as one: `vars/makeItWatermark.groovy`, with the script and the allowed list under `resources/`).
The organization's own pipeline calls `makeItWatermark()` before it builds or deploys anything.
What makes it a gate, not a courtesy:

- the pipeline definition and the library come from the organization, never from the project's
  branch, and the library's version cannot be overridden from a `Jenkinsfile`;
- the script runs with `ALLOWED_RELEASES` set, so only listed make-it releases pass (pinned by
  digest) and the hostile-code check runs first;
- GitHub requires that Jenkins status on the default branch, with Jenkins' own GitHub App chosen
  as its expected source, so nobody else can post a passing status under that name;
- Jenkins is also what deploys, so "no pass, no deploy" is the order of the stages. There is no
  attestation on this path: that is GitHub Actions only.

Checked against Jenkins' shared-library docs and GitHub's ruleset docs, 2026-11-16. Not yet run in
a Jenkins.

## 4. Always on (set up once by the Claude administrator)

Claude Code managed settings (a `managed-settings.json` pushed by device management, or the
server-managed settings of a Team or Enterprise plan) cannot be overridden by a user, and a
managed hook cannot be switched off from user settings (checked against Claude Code's docs,
2026-11-16). This hook keeps the record current after every turn, in any make-it project:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
                     "command": "python3 -I \"$HOME/.claude/make-it/scripts/watermark.py\" hook",
                     "timeout": 10 } ] }
    ]
  }
}
```

`watermark.py hook` prints nothing, never fails a turn, and does nothing outside a make-it
project. The managed `CLAUDE.md` (same folder as the managed settings) is where the organization
states that coding goes through the make-it skills; it loads in every session and a user cannot
exclude it. It is guidance, not enforcement: the enforcement is the check in GitHub.

Limits to know: someone with administrator rights on the computer can edit the managed file, and
managed settings cover Claude Code only. That is why part 3 is the gate and this part is not.
