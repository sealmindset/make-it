# /ship-it Integration Guide

This reference tells /make-it how and when to hand off to /ship-it for deployment, and defines the full deployment lifecycle from local Docker sandbox to production.

---

## The User's World

The vibe coder never touches infrastructure, never fixes code manually, and never interacts with DevOps directly. Their entire experience is:

1. **Describe** what they want (via /make-it or /resume-it)
2. **Verify** it works the way they envision (via /try-it)
3. **Say "ready"** (via /ship-it)

Everything else -- code quality, security scanning, infrastructure provisioning, deployment -- is automated or handled by DevOps.

---

## AI Provider on Ship (who pays for the AI)

If the app was built with `ai_providers.primary == "claude_agent"` (the default for
single-user local apps -- it uses the builder's personal Claude Code subscription token),
that default is **local-individual only** and must NOT carry into a shared/production deploy:

- A `CLAUDE_CODE_OAUTH_TOKEN` is single-identity, has subscription usage limits, and is not a
  deployment credential. The secret-leak scan (below) already blocks it from being committed;
  in addition, moving off it changes who pays for the AI, so nothing switches until the user
  picks the billing mode by name -- the billing ask below (high-stakes, `approval-block.md`):
  an Anthropic API key (pay per use), the org's enterprise provider, or keep it local. After
  the pick, tell the user to set the matching key in the deployment environment.
- Intent classification: `intent:experiment` may keep claude_agent (still local); `intent:shareable`
  and `intent:prod-ready` move off claude_agent only through that pick ("keep it local" means
  they don't ship to others yet). Never write the personal token into `.ship-it.yml`, workflows,
  or any committed file.

### The billing ask

The ship hand-off of /make-it, /resume-it and /retrofit-it asks this first, before its go-live
text, while the app uses claude_agent.

**If the app uses the claude_agent provider (Claude Code subscription):**
- This default is local-individual only, and moving off it changes who pays for the AI: a
  high-stakes ask (money, per the approval block). Before shipping to others/production, ask
  once -- fill the evidence from what you saw (`AI_PROVIDER=claude_agent` in `.env`, or
  `ai_providers.primary` in app-context.json):
  "Before other people use your app, one money decision is yours. Its AI features run on your
  own Claude Code subscription (I saw [`AI_PROVIDER=claude_agent` in your settings file (.env)]).
  That sign-in is just for you: it can't be shared with other people or put on a server, and
  it has your plan's usage limits.
  What changes: who pays for the AI, and how. With an Anthropic API key, every AI request is
  billed per use to whoever owns the key -- the more people use it, the more it costs. To cap
  the cost, set a monthly limit in the provider's account settings, where it offers one. With
  your organization's AI provider, your organization's account pays, under its own rules. Your
  copy on this computer stays on your subscription either way.
  Undo: switching back means changing the same places again -- the two app files I'd update,
  and the settings where the shared app runs. Deleting the key is what stops the charges (for
  your organization's provider, your IT team removes it): new charges stop at once, and the
  shared app's AI stops until you pick again. AI use already billed can't be taken back.
  What's unusual: until now the AI cost nothing beyond your plan.
  The one thing to check: who will pay once others use it -- you, or your organization? Not
  sure? Pick 'Keep it local'.
  Pick one by name:
  - **Use an Anthropic API key (pay per use)** -- billed per use to the key's owner; the key
    goes into the settings where the shared app runs (your DevOps team sets it, or you add it
    in your hosting settings), never in your code.
  - **Use my organization's provider** -- billed to your organization's account; your IT team
    gives you its address and key.
  - **Keep it local, don't ship to others yet** -- nothing changes; it stays on your
    subscription, just for you."
- **Wait for their pick.** Nothing switches before the pick. A plain yes, "ok" or "go ahead"
  is not a pick -- ask them to pick one by name. Then:
  - **Use an Anthropic API key** -> set ai_providers.primary to "anthropic" in app-context.json
    and `AI_PROVIDER=anthropic` in `.env.example`. Leave their own `.env` alone: it stays
    `AI_PROVIDER=claude_agent`, so the copy on their computer keeps running on their plan. Tell
    them in one line which files changed, that their settings file (.env) did not, and that
    `AI_PROVIDER=anthropic` and the key (`ANTHROPIC_API_KEY`) go into the settings where the
    shared app runs (their DevOps team sets them, or they add them in their hosting settings),
    never in a committed file.
  - **Use my organization's provider** -> the same with "anthropic_foundry" (or the provider
    their organization names), its endpoint and key.
  - **Keep it local, don't ship to others yet** -> change nothing in the app or its settings.
    Skip the hand-off's go-live text; tell them `/ship-it save` backs up their work to GitHub
    as a draft, without putting the app live for anyone, and that this question comes first
    when they want others to use it. Record it in `.make-it-state.md`, as one line under
    `## Before sharing`:
    `- Open: who pays for the AI before others use the app (asked first at the next hand-off)`
- Whatever they pick, warn the user NEVER to commit or ship their personal
  CLAUDE_CODE_OAUTH_TOKEN (single-identity, subscription usage limits, not a deployment
  credential). Confirm it's only in .env (gitignored).
- When they pick a way to pay (an API key or their organization's provider), take the
  `- Open: who pays for the AI` line out of `## Before sharing` in `.make-it-state.md`, if
  it's there.

## What /ship-it Does

/ship-it is a Claude Code skill that automates the path from local code to a pull request. The developer runs one command: `/ship-it`. That's it.

**Behind the scenes, /ship-it:**
1. Detects the repo, branch, auth status, and project type
2. Reads the DevOps-managed .ship-it.yml config
3. **Scans dependencies for known vulnerabilities** (pip-audit for Python, npm audit for Node.js)
4. **Auto-fixes vulnerable packages** by upgrading to patched versions
5. Creates a branch, commits changes (including the package fixes), pushes
6. Generates a workflow if the repo has none yet (it never overwrites one): a thin caller of the
   org's shared reusable workflow when `.ship-it.yml` names one (see Workflow Generation)
7. Creates a PR with labels, reviewers, description, a "Pending safety updates" list of the
   dependency alerts it could not fix, and, for `intent:prod-ready`, the go-live checklist (its
   left-out lines: see Left-out items before production)
8. Reports back: "Done! Your code is on its way." with the PR link, and "The team will review
   it and let you know when it's live."

**Two modes:**
| Command | What it does |
|---------|-------------|
| `/ship-it` | Ship for deployment. Creates PR, assigns reviewers, full safety checks. |
| `/ship-it save` | Save work in progress. Commits, pushes, creates draft PR. No reviewers; the pre-push checks (the secret leak scan among them) still run. |

**What /ship-it never does:**
- Force-push -- it always adds new commits to the PR branch
- Show CI logs, workflow names, or check names to the user
- Push to the deploy branch or trigger production deployments

### Git hygiene on the way to merge (see `git-operations.md`)

/ship-it itself never merges a PR. Whoever merges one applies the `/git-it` rules so nothing
lands stale or conflicting:
- **Branch off the latest `origin/main`**, commit atomically (Conventional Commits), stage only
  your own paths, and push feature branches with `--force-with-lease` (never plain `--force`).
- **Fresh CI before merge.** If `main` moved since the last green run, **rebase onto `main` and
  re-run CI** — never merge on stale green (green that predates a later `main` merge proves
  nothing). Watch checks to completion; verify the real state before claiming merged/green.
- **Triage the open-PR backlog (drop / refine / safe):** superseded (content already on `main`)
  → close + delete; conflicting or stale-CI → rebase + fresh CI + verify; clean + green + wanted
  → merge. Anything touching live/irreversible paths → verify on rehearsal/staging first.
- **Squash-merge + delete the branch.** In shared/multi-session repos, only delete branches you own.
- **Project board (`/backlog-it`, see `backlog-board.md`):** record each card's PR in `pr:` and how the
  fix is proved live in `signal:` when it opens; on merge, move each shipped card to `stage: Live` and set
  `checkAfter:` to the release that carries it -- a dated tag (`v2026.10.17`) or the date it goes out, never an
  undated tag (`status` flags those as never due) -- (`/backlog-it reconcile --prs` does the move from `pr:`, never
  without a `signal:`); after the live check passes against the original report, to `Checked` and `done`.

### Safety steps /ship-it doesn't run yet

/ship-it doesn't run these safety steps yet: its SKILL.md (v1.3.0) has none of them, and card
E02-S39 adds them. Their sections describe them as /ship-it will run them.
- **The secret leak scan before every push**, /ship-it save included (Pre-push secret leak scan,
  below)
- **The switch off the builder's personal Claude token** on a shareable or prod-ready ship (AI
  Provider on Ship)
- **The billing ask** before that switch (The billing ask; the ship hand-off of /make-it,
  /resume-it and /retrofit-it asks it today)
- **The left-out rules** (Left-out items before production): the production ask, the auto-fix
  rule, the stop on a found secret, and the go-live lines

### Pre-push secret leak scan (runs before every push, /ship-it save included)

Before it commits and pushes, /ship-it scans the diff for what looks like a password, API key,
token or private key -- including `CLAUDE_CODE_OAUTH_TOKEN` / `sk-ant-oat` Claude Code
subscription tokens. It skips .example files, TODOs and placeholder values. If it finds nothing,
it goes on silently.

When it finds one, it STOPS and explains in plain language: "I found what looks like a secret in
your changes." It moves the secret to .env (gitignored) and puts an env var reference in its
place. A personal Claude Code token must never be committed or shipped.

A secret that belongs to a left-out item is never moved here: see Left-out items before
production.

### What make-it runs before /ship-it

These run before the app reaches /ship-it, so /ship-it doesn't repeat them:
- **AI safety** (if the app has AI features): build-verify runs the NeMo Guardrails basic suite
  (check AI09, 18 test cases) and fixes what fails. /nemo-it runs the full suite (60+ test cases
  across the 6 categories) and writes the AI safety attestation,
  `docs/attestations/nemo-it/YYYY-MM-DD-vN.md`: the attestation GRC asks for before production
  comes from /nemo-it, and /fix-it fixes its findings. No skill puts an attestation summary in
  the PR.
- **Prompt edits flagged `risk_flag=true`** in `prompt_audit_log`: no skill flags them for
  security review at ship.
- **Code quality**: build-verify's checks (`build-standards.md`: lint and type-check, migrations,
  `.env.example`) and its `docker compose up --build`; the quality-gate workflow (check Q13)
  runs lint, type-check and tests again on every PR.

---

## Deployment Lifecycle

The full path from local app to production. The user only participates at verification checkpoints.

```
LOCAL DEVELOPMENT (user's Docker sandbox)
  /make-it        -> Build app, push code to GitHub
  /resume-it      -> Iterate (features, security fixes, testing)
  /try-it         -> User verifies: "Does it do what I want?"
                     |
                     v
CONTINUOUS QUALITY (automated, invisible to user)
  Security Scanner -> Scans repo continuously, reports issues (optional)
  /resume-it      -> Auto-fixes scan findings, runs tests, verifies
                     (user never sees this -- just confirms app still works)
                     |
                     v
SHIP (user triggers)
  /ship-it        -> Dependency scan and fixes -> PR
                     |
                     v
DEVOPS PREFLIGHT (automated, DevOps-owned)
  CI/CD Automation -> Scans PR: security, compliance, IaC, dependencies
                     |
                     +-- Issues found?
                     |     -> BOT auto-remediates what it can
                     |     -> DevOps team handles the rest
                     |     -> Sends back to user for verification
                     |        |
                     |        v
                     |     /try-it -> User verifies app still works
                     |     /ship-it -> Back to DevOps for recheck
                     |        |
                     |        v
                     |     (loop until clean)
                     |
                     +-- All clear?
                           -> Deploy to dev environment
                              |
                              v
DEV ENVIRONMENT
  User tests in dev environment
  User confirms via /ship-it: "This is ready for production"
  (see Left-out items before production)
                     |
                     v
PRODUCTION GATE (DevOps-owned)
  CI/CD Automation -> Production preflight (stricter checks)
  DevOps team      -> Final review
                     |
                     +-- Passes -> Deploy to prod
                     +-- Fails  -> Remediate, loop back to user verification
```

### Left-out items before production

/ship-it itself asks about each left-out `[BLOCK]` item, never the DevOps-owned gate or CI: the
user never talks to DevOps. It asks at its Intent Classification, as soon as the user picks
`intent:prod-ready`, before anything goes to the production gate. The dev environment's "This is
ready for production" comes through /ship-it the same way.

/ship-it reads the left-out record on every ship, through `left-out-record.md` (its read
steps, the rule every reader follows, and what makes an item `[BLOCK]`). So its own auto-fixes --
the package upgrades and the pre-push secret leak scan -- never put a left-out item back, and
never report one of its checks as FAIL. A left-out `[BLOCK]` item is neither silently blocked nor
silently passed: no production check fails the ship on it, or skips it, without the production
ask below.

One guard holds for a left-out item on every push, whatever the intent, /ship-it save included
(the secret leak scan runs on save too): a found secret is never sent, whatever is left out.
When the secret leak scan finds a secret that belongs to a left-out item (for example "Move the
passwords and keys out of your code", check X01), /ship-it stops before the push and sends
nothing. It names the left-out item and
the `file:line` where the secret is (never its value), and gives the same next step as the
production ask's **Add [item] first**: "Run /resume-it and say 'add [item]'; it checks with you
before it adds it. Then type /ship-it again." Before that, it says why in plain words: "I found
what looks like a key there. Once a key is sent, anyone who can see your code can use it, and that
can't be taken back." /ship-it never moves the secret itself here (not to `.env`, not anywhere),
never offers "Ship with [item] left out" once a secret is found, and that check is never reported
as "not checked" (`left-out-record.md`).

The production ask is high-stakes, so it is active confirmation (`approval-block.md`). It is
never a plain yes. It names each left-out `[BLOCK]` item, says what it guards in plain
words (for sign-in: "only the people you let in can open your app"), and says that the user
left it out by their choice. It also says why it comes up now: each one should be in place
before an app goes live. Each item gets its own pick, never one answer for all of them. For
each one, the user picks:
- **Ship with [item] left out** -- say what that means while the app is live (for sign-in:
  "anyone with the link can open your app"), and the undo: "You can add it later with /resume-it
  and ship again, but what people saw meanwhile can't be taken back."
- **Add [item] first** -- say: "/ship-it stops here: nothing is sent, and nothing goes live until
  it is in. Run /resume-it and say 'add [item]'; it checks with you before it adds it. Then type
  /ship-it again." (`left-out-record.md`)

/ship-it records each "Ship with [item] left out" pick in the PR's go-live checklist, by name:
the item, what it guards, and "left out by the user's choice, confirmed at ship". Each /ship-it,
before it pushes, rewrites those lines from the record and the picks as they stand then: an item
the user has since added comes off the checklist, and its checks count like any `[BLOCK]` item's.
A change of mind at the dev environment's confirmation updates its line too. DevOps can still hold
the ship on it at the final review; then the automation tells the user which item, by name, in a
PR comment that gives the next step: "Run /resume-it and say 'add [item]', then type /ship-it
again." When the DevOps team fixes an item the user chose to ship with, the automation tells the
user which item, by name, in a PR comment that asks them to keep it or take it out again, with the
next step: "Run /resume-it and say which you mean: 'keep the team's fix for [item]' or 'take [item]
out again', then type /ship-it again."
Their answer updates the record (`left-out-record.md`).

A left-out item that is not `[BLOCK]` doesn't add to this ask.

---

## Phase Ownership

| Phase | Owner | User's Role |
|-------|-------|-------------|
| Local development | User + /make-it + /resume-it | Describe what they want, verify it works |
| Security scanning | Automated (optional) | None (invisible) |
| Security remediation | /resume-it (automated) | Verify app still works after fixes |
| /ship-it PR creation | Automated | Type `/ship-it` |
| DevOps preflight scan | CI/CD automation | None (wait) |
| Preflight remediation | CI/CD automation + DevOps team | Verify app still works after fixes |
| Deploy to dev | DevOps | None (wait) |
| Dev environment testing | User | "Does it work how I want?" |
| Production gate | CI/CD automation + DevOps team | Confirm prod-ready via /ship-it (see Left-out items before production) |
| Deploy to prod | DevOps | None (notified when live) |

---

## Security Scanner Integration (Optional)

If your organization uses a security scanning platform, /resume-it can automatically remediate findings. The scanner integration is pluggable — configure it based on your tool.

### Supported Scanners

Configure in `app-context.json`:

| Scanner | Type | How Findings Arrive |
|---------|------|-------------------|
| AuditGithub | Custom platform | GitHub Issues (labeled) + REST API |
| GitHub Advanced Security | Built-in | GitHub Security tab + API |
| Snyk | SaaS | GitHub Issues or webhooks |
| SonarQube | Self-hosted | API polling |
| None | - | Manual security review |

### Example Integration Pattern (Hybrid: GitHub Issues + REST API)

This section describes one possible integration approach. Your organization may use a different pattern.

Security scanners and /resume-it can communicate through two channels:

```
NOTIFICATION (Scanner → GitHub Issues):
  Lightweight, always visible, triggers /resume-it awareness

REMEDIATION (resume-it → Scanner REST API):
  Rich finding data, AI diffs, status updates
```

**Why hybrid:** /resume-it is ephemeral (only runs when user invokes it). GitHub Issues provide persistent visibility. The REST API provides the rich data needed to actually fix things.

### Channel 1: GitHub Issues (Scanner → repo)

The scanner creates/updates GitHub Issues on the repo for each finding:

**Issue format:**
```markdown
Title: [CRITICAL] Hardcoded AWS secret in config/settings.py
Labels: auditgithub, severity:critical, type:secret
Body:
  **Finding ID:** f47ac10b-58cc-4372-a567-0e02b2c3d479
  **Scanner:** gitleaks
  **Severity:** critical
  **Risk Score:** 92/100
  **File:** config/settings.py:47
  **First Seen:** 2026-03-10T14:30:00Z

  **Summary:** Hardcoded AWS access key detected in configuration file.

  **AI Recommendation:** Move secret to environment variable and .env file.
  AI confidence: 0.95

  ---
  _This issue was created by the security scanner. Do not close manually --
  it will auto-close when the finding is resolved._
```

**Issue lifecycle:**
- Scanner creates issue on new finding
- Scanner updates issue body if finding changes (rescan updates risk score, AI retriage)
- Scanner auto-closes issue when finding status becomes `resolved` (confirmed by rescan after push)
- Labels updated if severity changes

### Channel 2: REST API (/resume-it → Scanner)

/resume-it calls the scanner API for rich finding data and to report fixes.

**Authentication:** API key per repo, stored in `.env`:
```bash
# .env (gitignored)
SECURITY_SCANNER_API_URL=https://your-scanner-domain.example.com
SECURITY_SCANNER_API_KEY=scanner_xxxxxxxxxxxxxxxxxxxx
```

**API calls /resume-it makes:**

| Step | Method | Endpoint | Purpose |
|------|--------|----------|---------|
| 1. Discover | `GET` | `/findings/paginated?repo_name={repo}&status=open` | Get all open findings for this repo |
| 2. Detail | `GET` | `/findings/{finding_id}` | Get full finding with `ai_remediation_diff` |
| 3. Fix | _(local)_ | Apply `ai_remediation_diff` to codebase | Use scanner's AI-generated fix |
| 4. Verify | _(local)_ | Run tests | Confirm fix doesn't break anything |
| 5. Push | _(local)_ | `git commit && git push` | Trigger scanner rescan |
| 6. Report | `PATCH` | `/findings/{finding_id}/status` | Mark as resolved with resolution notes |

**Request/response examples:**

```bash
# Step 1: Get open findings
GET /findings/paginated?repo_name=my-app&status=open&severity=critical,high
Headers: Authorization: Bearer scanner_xxxxxxxxxxxxxxxxxxxx

Response: {
  "items": [
    {
      "id": "f47ac10b-...",
      "severity": "critical",
      "title": "Hardcoded AWS secret in config/settings.py",
      "file_path": "config/settings.py",
      "line_start": 47,
      "ai_remediation_text": "Move secret to environment variable...",
      "ai_remediation_diff": "--- a/config/settings.py\n+++ b/config/settings.py\n@@ -45,3 +45,3 @@\n-AWS_KEY = 'AKIA...'\n+AWS_KEY = os.getenv('AWS_ACCESS_KEY_ID')",
      "ai_triage_recommendation": "true_positive",
      "ai_triage_confidence": 0.95,
      "risk_score": 92
    }
  ],
  "total": 3,
  "page": 1
}

# Step 6: Mark resolved after fix
PATCH /findings/f47ac10b-.../status
Headers: Authorization: Bearer scanner_xxxxxxxxxxxxxxxxxxxx
Body: {
  "status": "resolved",
  "resolution": "fixed",
  "resolution_notes": "Applied AI remediation diff. Secret moved to .env."
}
```

### Example: AuditGithub Remediation Flow

AuditGithub is a custom security scanning platform. Here's how /resume-it integrates with it:

```
AuditGithub scans repo (on push or cron schedule)
  → Stores findings in database (with AI triage + remediation diffs)
  → Creates GitHub Issues on repo (one per finding)

User runs /resume-it
  → Step 1: gh issue list --label "auditgithub" --state open
  → Step 2: For each issue, extract finding_id from issue body
  → Step 3: GET /findings/{id} → full detail with ai_remediation_diff
  → Step 4: Apply ai_remediation_diff to codebase
  → Step 5: Run tests → verify fix doesn't break anything
  → Step 6: git commit + push
  → Step 7: PATCH /findings/{id}/status → resolved
  → AuditGithub detects push → rescans → confirms finding resolved → auto-closes GitHub Issue

If fix changes app behavior:
  → Pause, tell user: "Run /try-it to check everything still works"
```

### What the user sees

Nothing, unless a fix changes how the app behaves. Then they get:
"I made some updates to keep your app secure. Can you check that everything still works the way you want? Just run /try-it."

### Integration Requirements

If building a custom scanner integration, the minimum requirements are:

| Feature | Description | Priority |
|---------|-------------|----------|
| Finding notification | Notify /resume-it of findings (GitHub Issues, webhooks, or API polling) | Required |
| Finding detail API | Provide full finding data including remediation guidance | Required |
| Status update API | Accept status updates when findings are resolved | Required |
| Authentication | API keys or OAuth scoped appropriately | Required |
| Auto-close on resolve | Close notifications when findings confirmed resolved | Nice to have |

---

## CI/CD Automation Contract (Optional)

A CI/CD automation service (DevOps BOT, GitHub Actions workflow, or similar) can scan PRs created by /ship-it before code reaches any deployed environment. This is an optional but recommended pattern.

### Trigger

The automation activates when:
- A PR is created by /ship-it (detected by label, branch naming convention, or .ship-it.yml presence)
- A PR is re-submitted after remediation (re-run on new commits)

### What the automation checks

| Category | Checks | Severity |
|----------|--------|----------|
| **Security** | Dependency vulnerabilities (CVEs), secret detection, OWASP top 10 patterns | Critical / High |
| **Compliance** | License compatibility, approved dependency list, org policy adherence | High |
| **Infrastructure** | Terraform validation (`terraform validate`, `terraform plan`), resource naming conventions, tagging policy | High |
| **Code Quality** | Linting rules, test coverage thresholds, build success | Medium |
| **Container** | Dockerfile best practices, base image approval, no root user, image size | Medium |
| **Configuration** | .env.example completeness, no hardcoded secrets, env var naming conventions | High |

### Remediation flow

```
Automation scans PR
  |
  +-- Critical/High issues found?
  |     |
  |     +-- Auto-remediable? (dependency updates, lint fixes, Dockerfile adjustments)
  |     |     -> Automation commits fix to PR branch
  |     |     -> Re-runs checks
  |     |
  |     +-- Requires human judgment? (architecture changes, breaking updates, policy exceptions)
  |           -> DevOps team reviews and fixes
  |           -> Commits fix to PR branch
  |
  +-- Medium/Low issues found?
  |     -> Automation commits auto-fixes where possible
  |     -> Remaining items logged as follow-up (don't block deployment)
  |
  +-- After remediation:
        -> Notify user: "We made some updates to your app for security/compliance.
           Please verify it still works: run /try-it"
        -> User runs /try-it, confirms
        -> User runs /ship-it to re-submit
        -> Automation re-scans (loop until clean)
```

### Communication contract

**Automation -> User notifications** (via GitHub PR comments, plain language):
- "Your app is being reviewed by our automation. You don't need to do anything -- we'll let you know when it's ready."
- "We made a few updates to keep your app secure. Please check that everything still works by running `/try-it` in your project."
- "All checks passed! Your app is being deployed to the dev environment. We'll let you know when it's ready to test." With a left-out item, it adds: "[item] wasn't checked: you left it out."
- When DevOps holds the ship at the final review on an item the user left out, the automation tells the user which item, by name, with the next step: "Run /resume-it and say 'add [item]', then type /ship-it again."
- When the DevOps team fixes an item the user chose to ship with, the automation tells the user which item, by name, in a PR comment that asks them to keep it or take it out again (Left-out items before production).

**Automation -> DevOps team notifications** (via internal channels):
- PR scan results with detailed findings
- Items requiring human judgment
- Deployment approval requests

**User -> Automation** (implicit, via /ship-it):
- Re-submitting a PR (new /ship-it after verification) signals "user has verified, ready for recheck"

### What the automation does NOT do

- Modify application behavior or business logic
- Change what the app does from the user's perspective
- Deploy without passing all checks
- Deploy to production without explicit DevOps team approval
- Communicate in technical jargon to the user
- Block the gate on a left-out item the user chose to ship with, remediate it, or put it back.
  It is reported to DevOps by name, and its checks don't count against "all checks" above.
  The automation reads which items the user chose from the PR's go-live checklist.

---

## Infrastructure & Terraform

/make-it generates Terraform configuration (Prompt #5) as a **DevOps handoff artifact**, not something the user applies.

### What gets generated

| File | Purpose |
|------|---------|
| `infrastructure/main.tf` | Cloud resources the app needs |
| `infrastructure/variables.tf` | Configurable values (resource names, SKUs, tags) |
| `infrastructure/outputs.tf` | Values needed by the app (connection strings, URLs) |
| `infrastructure/versions.tf` | Provider version constraints |
| `infrastructure/backend.tf` | State backend (configured for chosen cloud provider) |
| `infrastructure/environments/` | Per-environment tfvars |

### Environment model

| Environment | Namespace | Applied By |
|-------------|-----------|------------|
| Dev | `{app-name}-dev` | CI/CD pipeline |
| Staging | `{app-name}-staging` | DevOps team |
| Prod | `{app-name}-prod` | DevOps team (with approval gate) |

### Terraform workflow (DevOps-owned)

1. /make-it generates Terraform as part of the build
2. /ship-it includes it in the PR
3. CI/CD automation validates: `terraform fmt -check`, `terraform validate`, `terraform plan`
4. Plan output posted as PR comment for DevOps team review
5. After PR merge + deployment approval: `terraform apply` by pipeline
6. Outputs (connection strings, URLs) fed into app's deployment config

**The user never runs Terraform.** They don't need to know it exists.

---

## .ship-it.yml Configuration

/ship-it uses a single config file with three sections, each owned by a different role:

```yaml
# APP -- What is being deployed (auto-populated by /make-it, or filled by developer)
app:
  name: "TaskHub"
  slug: "task-hub"
  stack: "fastapi-nextjs"
  services:
    - name: backend
      dockerfile: backend/Dockerfile
      port: 8000
      health_check: /health
    - name: frontend
      dockerfile: frontend/Dockerfile
      port: 3000
      health_check: /
  database:
    engine: postgresql
    version: "16"
  auth:
    provider: oidc

# INFRA -- Where and how to deploy (filled by DevOps)
infra:
  provider: aws            # aws | azure | ""
  aws:
    region: us-east-1
    account_id: "123456789012"
    ecr_registry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    ecs:
      cluster_name: "apps-cluster"

# DEPLOYMENT -- How the pipeline behaves
deployment:
  environments:
    dev: dev
    production: production
  reviewers:
    - devops-lead
  strategy: rolling
```

### Config Merge Priority (highest wins)

1. `.ship-it.yml` values (DevOps overrides everything)
2. `app-context.json` values (from /make-it)
3. Auto-detected values (stack detection from package.json, requirements.txt, etc.)
4. Sensible defaults

### What /make-it Provides

When /ship-it runs on a project built by /make-it, it reads:

| Source | What It Provides |
|--------|-----------------|
| `.make-it/app-context.json` | App name, slug, stack, services, database, auth |
| `.make-it-state.md` | Build-verify status (confirms app works locally), and the left-out record (read through `left-out-record.md`) |
| Project files | Stack auto-detection (fallback if app-context missing) |

/ship-it auto-generates the `app` section of `.ship-it.yml` from app-context.json. The `infra` section starts empty -- DevOps fills it in after the first PR.

### Intent Classification

/ship-it asks up to 3 yes/no questions to classify intent:

| Intent | Label | Deploy Target |
|--------|-------|---------------|
| Experiment | `intent:experiment` | None |
| Shareable | `intent:shareable` | Dev only |
| Prod-ready | `intent:prod-ready` | Dev + Prod |

With a /make-it project, the questions about the app are skipped (stack, services, auth already
known); the 3 intent questions are still asked, unless `.make-it-state.md` shows the app was
verified with /try-it and the user said it is ready for production (then it is `intent:prod-ready`).

On `intent:prod-ready`, if the record has a left-out `[BLOCK]` item (`left-out-record.md` says how to tell), /ship-it's left-out ask comes next -- see Left-out items before production.

### Workflow Generation

If the repo has no workflow yet, /ship-it generates a GitHub Actions workflow (it never
overwrites one). A `deployment.reusable_workflow` comes first; otherwise the `infra` section decides:

| Infra State | Workflow Generated |
|-------------|-------------------|
| `infra.provider: aws` | ECR login, Docker build per service, ECS update-service |
| `infra.provider: azure` | ACR login, Docker build, kubectl set image |
| `infra.provider: ""` (empty) | Placeholder with "Deployment pending DevOps configuration" |
| `deployment.reusable_workflow` set | Thin caller referencing the shared workflow |

---

## When /make-it Hands Off to /ship-it

After the build phase completes and the user has a working local application, /make-it:

1. **Confirms the app works locally** -- asks the user to verify
2. **Explains what happens next** in plain language
3. **Checks prerequisites:**
   - Git repo exists (should already from project setup)
   - Code is in a clean state
   - .gitignore is properly configured
4. **Invokes /ship-it** which handles everything else

---

## What the User Needs Before /ship-it

| Requirement | How to get it | One-time? |
|------------|--------------|-----------|
| Claude Code installed | Already have it (they're using /make-it) | Yes |
| /ship-it plugin installed | /make-it can guide installation | Yes |
| GitHub CLI (gh) installed | brew install gh | Yes |
| GitHub CLI authenticated | gh auth login | Yes |
| Git installed | Pre-installed on most systems | Yes |
| Code cloned locally | Already done during /make-it | Yes |

---

## Transition Script (what /make-it tells the user)

When transitioning from build to ship:

"Your application is built and working locally. The next step is getting it out there so others can use it.

When you type /ship-it, here's what happens:
- Your code gets saved and sent for review
- Our automated systems check it for security and quality
- If anything needs fixing, it gets fixed automatically -- you just verify your app still works
- Once everything passes, it gets deployed

You don't need to do anything technical -- just verify your app works the way you want at each checkpoint.

When you're ready, just type: **/ship-it**

If you want to save your progress first without deploying, type: **/ship-it save**

That's it -- you just built your first app!"
