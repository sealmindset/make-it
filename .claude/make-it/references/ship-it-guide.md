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

## What /ship-it Does

/ship-it is a Claude Code skill that automates the path from local code to a pull request. The developer runs one command: `/ship-it`. That's it.

**Behind the scenes, /ship-it:**
1. Detects the repo, branch, auth status, and project type
2. Reads the DevOps-managed .ship-it.yml config
3. Creates a branch, commits changes, pushes
4. Generates a caller workflow referencing the org's shared reusable workflow
5. Creates a PR with labels, reviewers, description, and go-live checklist
6. Reports back: "Done! The team will take it from here."

**Two modes:**
| Command | What it does |
|---------|-------------|
| `/ship-it` | Ship for deployment. Creates PR, assigns reviewers, full safety checks. |
| `/ship-it save` | Save work in progress. Commits, pushes, creates draft PR. No review. |

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
  /ship-it        -> Creates PR, hands off to DevOps
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
  User confirms: "This is ready for production"
                     |
                     v
PRODUCTION GATE (DevOps-owned)
  CI/CD Automation -> Production preflight (stricter checks)
  DevOps team      -> Final review
                     |
                     +-- Passes -> Deploy to prod
                     +-- Fails  -> Remediate, loop back to user verification
```

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
| Production gate | CI/CD automation + DevOps team | Confirm prod-ready |
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
- "All checks passed! Your app is being deployed to the dev environment. We'll let you know when it's ready to test."

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
