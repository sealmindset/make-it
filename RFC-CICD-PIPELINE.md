# RFC: CI/CD Pipeline for /make-it Applications

**Status:** Draft
**Authors:** DevOps Skills Team
**Date:** 2026-03-16
**Audience:** DevOps Engineering Team
**Repos:** [make-it](https://github.com/sealmindset/make-it) | [ship-it](https://github.com/sealmindset/ship-it) | [harness-it](https://github.com/sealmindset/harness-it)

---

## 1. Purpose

This RFC defines the complete delivery pipeline for applications built with `/make-it` and shipped with `/ship-it`. It proposes the GitHub Actions workflows, security scanning gates, environment promotion strategy, infrastructure provisioning process, and rollback procedures that the DevOps team needs to build, own, and operate.

The goal: a developer with zero infrastructure knowledge types `/ship-it` and their code reaches production through a fully automated, auditable, and DevOps-controlled pipeline.

---

## 2. Scope

This RFC covers:

| Area | What's Defined |
|------|---------------|
| Pipeline architecture | End-to-end flow from local build to production |
| GitHub Actions workflows | Shared reusable workflow (proposed) + per-app caller workflow (generated) |
| Security scanning | Three-layer model: pre-push, PR scan, continuous scan |
| Environment promotion | dev → prod (staging-ready) with gates at each transition |
| Infrastructure provisioning | Terraform pipeline for app infrastructure |
| Rollback strategy | Automated and manual rollback procedures |
| Ownership boundaries | What the developer owns vs. what DevOps owns |
| Compliance tagging | Optional compliance labels for regulated workloads |

This RFC does NOT cover:
- How `/make-it` builds applications (see make-it CLAUDE.md)
- Application architecture decisions (see design-blueprint.md)
- Identity provider configuration (organization-specific)

---

## 3. Pipeline Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  DEVELOPER (local machine)                                           │
│                                                                      │
│  /make-it ──► /try-it ──► /ship-it                                  │
│     build       verify      pre-push scan ──► commit ──► push ──► PR│
│                             (dep-audit)                              │
└────────────────────────────────────────┬─────────────────────────────┘
                                         │
                                         │ Pull Request created
                                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GITHUB ACTIONS (DevOps-owned shared workflow)                       │
│                                                                      │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────────┐       │
│  │ Build & Test │──►│ Security Scan│──►│ Deploy to Dev      │       │
│  │             │   │              │   │                    │       │
│  │ • Docker    │   │ • Dependencies│   │ • Push to ECR     │       │
│  │   build     │   │ • Secrets    │   │ • ECS update      │       │
│  │ • Unit tests│   │ • OWASP     │   │ • Run migrations  │       │
│  │ • Lint      │   │ • IaC valid  │   │ • Health check    │       │
│  └─────────────┘   │ • Container │   └────────────────────┘       │
│                     │ • License   │              │                   │
│                     └──────┬───────┘              │                   │
│                            │                      │                   │
│                     Issues found?                  │                   │
│                       │    │                      │                   │
│                  Yes  │    │ No                   │                   │
│                       ▼    ▼                      ▼                   │
│               ┌────────────────┐        ┌────────────────────┐       │
│               │ Auto-Remediate │        │ Dev Smoke Tests    │       │
│               │ • dep upgrades │        │ • Health checks    │       │
│               │ • lint fixes   │        │ • Auth flow        │       │
│               │ • Dockerfile   │        │ • API endpoints    │       │
│               └───────┬────────┘        └────────┬───────────┘       │
│                       │                          │                   │
│                Can't auto-fix?            Passes?                    │
│                       │                     │    │                   │
│                       ▼                No   │    │ Yes               │
│               ┌────────────────┐     ┌──────┘    ▼                   │
│               │ Notify DevOps  │     │  ┌────────────────────┐       │
│               │ for manual fix │     │  │ Production Gate    │       │
│               └───────┬────────┘     │  │ • DevOps approval  │       │
│                       │              │  │ • Compliance check │       │
│                       │              │  │ • Stricter scans   │       │
│                       ▼              │  └────────┬───────────┘       │
│               ┌────────────────┐     │           │                   │
│               │ Kick back to   │◄────┘    Approved?                  │
│               │ developer for  │              │    │                  │
│               │ /try-it verify │         No   │    │ Yes              │
│               └────────────────┘              │    ▼                  │
│                                               │  ┌──────────────┐    │
│                                               │  │ Deploy to    │    │
│                                               │  │ Production   │    │
│                                               │  └──────────────┘    │
│                                               │                      │
│                                               ▼                      │
│                                        ┌──────────────┐              │
│                                        │ Remediate +  │              │
│                                        │ resubmit     │              │
│                                        └──────────────┘              │
└──────────────────────────────────────────────────────────────────────┘
                                         │
                                         │ Continuous (post-deploy)
                                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  CONTINUOUS SCANNING (AuditGithub or equivalent)                     │
│                                                                      │
│  Scans repo on schedule ──► Findings as GitHub Issues                │
│  /resume-it auto-fixes ──► Developer verifies via /try-it            │
│  /ship-it re-submits ──► Pipeline re-runs                            │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Ownership Boundaries

### 4.1 What the Developer Owns

| Responsibility | How | Tools |
|---------------|-----|-------|
| Describe what the app does | Plain English conversation | `/make-it` |
| Verify the app works as intended | Click through in browser | `/try-it` |
| Say "ready to deploy" | One command | `/ship-it` |
| Verify after DevOps/security fixes | Click through in browser | `/try-it` |

The developer **never**:
- Writes CI/CD configuration
- Fixes security vulnerabilities manually
- Configures infrastructure
- Manages deployments
- Interacts with DevOps tooling directly

### 4.2 What /ship-it Owns (Automated)

| Responsibility | When | Details |
|---------------|------|---------|
| Pre-push dependency audit | Before git push | Scans all `requirements.txt` (pip-audit/PyPI) and `package-lock.json` (npm audit). Auto-upgrades vulnerable packages in-place. |
| Branch creation | On `/ship-it` | Creates `ship-it/{app-slug}` branch from main |
| .ship-it.yml generation | On `/ship-it` | Merges app-context.json + .ship-it.yml + auto-detection |
| Workflow generation | On `/ship-it` | Generates caller workflow referencing shared reusable workflow |
| PR creation | On `/ship-it` | Labels, reviewers, description, security audit summary, go-live checklist |
| Intent classification | On `/ship-it` | experiment / shareable / prod-ready (determines deploy target) |

### 4.3 What DevOps Owns

| Responsibility | When | Details |
|---------------|------|---------|
| Shared reusable workflow | Build once, maintain | The GitHub Actions workflow all apps call into (Section 5) |
| PR security scan | On every PR | Dependency, secret, OWASP, IaC, container, license scanning |
| Auto-remediation | On scan findings | Commit fixes to PR branch for what can be automated |
| Manual remediation | When auto-fix fails | DevOps engineer reviews and fixes |
| Developer notification | After remediation | Plain-language PR comment: "verify with /try-it" |
| Infrastructure provisioning | On first deploy | Apply Terraform from PR (Section 8) |
| Environment promotion | After dev verification | Promote from dev to production (Section 7) |
| Production gate | Before prod deploy | Stricter scans, approval, compliance check |
| Rollback | On failed deploy | Automated or manual rollback (Section 9) |
| Continuous scanning config | Ongoing | Configure AuditGithub / security scanner per repo |

### 4.4 Handoff Points (Developer ↔ DevOps)

```
Developer → DevOps:
  /ship-it creates PR
  "Here's my code. It works locally. Please deploy it."

DevOps → Developer:
  PR comment after remediation
  "We made some security updates. Please verify your app still works: run /try-it"

Developer → DevOps:
  /ship-it re-submits (new commit on PR branch)
  "I verified it. Everything works. Please continue."

DevOps → Developer:
  PR comment on deploy
  "Your app is live in dev. Test it at https://app-dev.example.com"
  "Your app is live in production. https://app.example.com"
```

---

## 5. Shared Reusable GitHub Actions Workflow

### 5.1 What Needs to Be Built

A single shared reusable workflow that all `/make-it` applications call. `/ship-it` generates a thin caller workflow per app that references this shared workflow.

**Repository:** `{org}/shared-workflows` (or equivalent)
**File:** `.github/workflows/make-it-deploy.yml`

### 5.2 Caller Workflow (Generated by /ship-it)

```yaml
# .github/workflows/ship-it.yml (auto-generated, lives in each app repo)
name: Ship-It Pipeline
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  ship-it:
    uses: {org}/shared-workflows/.github/workflows/make-it-deploy.yml@main
    with:
      app-slug: "deliverit"
      environment: dev
    secrets: inherit
```

### 5.3 Shared Workflow Structure

The reusable workflow has 5 jobs executed in sequence:

```yaml
jobs:
  # Job 1: Build + Test
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Detect stack
        # Read .ship-it.yml to determine build steps
      - name: Build Docker images
        # docker build per service defined in .ship-it.yml
      - name: Run unit tests
        # Stack-specific: pytest, jest, go test, etc.
      - name: Lint
        # Stack-specific linting
      - name: Push to ECR
        # Tag and push all service images

  # Job 2: Security Scan
  security-scan:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Dependency scan
        # pip-audit, npm audit, govulncheck (redundant with pre-push, catches drift)
      - name: Secret detection
        # gitleaks or trufflehog
      - name: OWASP check
        # dependency-check or Snyk
      - name: IaC validation
        # terraform validate, terraform fmt -check, tflint
      - name: Container scan
        # trivy or grype on built images
      - name: License compliance
        # license-checker or similar
      - name: Post results
        # Comment on PR with scan summary

  # Job 3: Auto-Remediate
  auto-remediate:
    needs: security-scan
    if: needs.security-scan.outputs.has-findings == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Fix dependencies
        # Upgrade vulnerable packages, commit to PR branch
      - name: Fix lint issues
        # Auto-format, commit to PR branch
      - name: Fix Dockerfile issues
        # Base image updates, remove root user, commit
      - name: Re-run scans
        # Verify fixes resolved the findings
      - name: Notify
        # If issues remain: notify DevOps channel
        # If behavior changed: comment on PR for developer verification

  # Job 4: Deploy to Dev
  deploy-dev:
    needs: [build, security-scan]
    if: needs.security-scan.outputs.has-blockers != 'true'
    runs-on: ubuntu-latest
    environment: dev
    steps:
      - name: Configure AWS credentials
      - name: Run database migrations
      - name: Update ECS services
      - name: Wait for healthy
      - name: Run smoke tests
        # Health checks, auth flow, API spot checks
      - name: Notify developer
        # "Your app is live in dev. Test at: https://..."

  # Job 5: Deploy to Production
  deploy-prod:
    needs: deploy-dev
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production  # Requires approval in GitHub environment settings
    steps:
      - name: Production preflight
        # Stricter scans, compliance checks
      - name: Configure AWS credentials
      - name: Run database migrations
      - name: Update ECS services (rolling)
      - name: Wait for healthy
      - name: Run production smoke tests
      - name: Notify developer
        # "Your app is live in production."
```

### 5.4 Workflow Inputs

The shared workflow accepts these inputs from the caller:

| Input | Required | Description |
|-------|----------|-------------|
| `app-slug` | Yes | Application identifier (from .ship-it.yml) |
| `environment` | No | Override deploy target (default: from intent label) |
| `skip-deploy` | No | Run build + scan only, no deployment |
| `compliance-tags` | No | Comma-separated compliance labels (see Section 10) |

### 5.5 Workflow Secrets

Configured at the organization or repository level:

| Secret | Scope | Purpose |
|--------|-------|---------|
| `AWS_ACCESS_KEY_ID` | Per environment | ECR push, ECS deploy |
| `AWS_SECRET_ACCESS_KEY` | Per environment | ECR push, ECS deploy |
| `AWS_REGION` | Organization | Default region |
| `AWS_ACCOUNT_ID` | Per environment | ECR registry |
| `SECURITY_SCANNER_API_KEY` | Organization | AuditGithub or equivalent |

---

## 6. Three-Layer Security Scanning Model

### 6.1 Layer 1: Pre-Push (Developer-Side, Automated by /ship-it)

**When:** Before `git push`, during `/ship-it` execution
**Owner:** /ship-it (dep-audit module)
**Scope:** Known dependency vulnerabilities only

| Check | Tool | Action on Finding |
|-------|------|-------------------|
| Python CVEs | pip-audit / PyPI advisory API | Auto-upgrade in requirements.txt |
| Node.js CVEs | npm audit | npm audit fix |

**What it catches:** Known CVEs in pinned dependency versions.
**What it misses:** Secrets, OWASP patterns, container issues, IaC problems, license violations.
**Why it exists:** Prevents the most common vulnerability class (outdated dependencies) from ever reaching GitHub. Reduces PR scan noise.

### 6.2 Layer 2: PR Scan (DevOps-Owned, GitHub Actions)

**When:** On every PR to main (Job 2 of shared workflow)
**Owner:** DevOps team
**Scope:** Comprehensive application and infrastructure security

| Category | Checks | Tool (Proposed) | Severity |
|----------|--------|-----------------|----------|
| Dependencies | CVEs, outdated packages, transitive vulns | pip-audit, npm audit, govulncheck | Critical / High |
| Secrets | Hardcoded keys, tokens, passwords in code | gitleaks | Critical |
| OWASP | SQL injection, XSS, command injection patterns | Semgrep or CodeQL | Critical / High |
| Infrastructure | Terraform validation, plan review, policy check | terraform validate, tflint, OPA | High |
| Container | Base image CVEs, root user, exposed ports, image size | Trivy or Grype | High / Medium |
| License | GPL contamination, unapproved licenses | license-checker | Medium |
| Configuration | .env.example completeness, no hardcoded URLs, env var naming | Custom script | Medium |

**Remediation flow:**

```
Finding detected
  │
  ├── Auto-remediable? (dep upgrade, lint fix, Dockerfile tweak)
  │     │
  │     └── Yes → Commit fix to PR branch → Re-scan → Continue
  │
  ├── Requires DevOps judgment? (architecture change, policy exception)
  │     │
  │     └── Yes → Notify DevOps channel → DevOps fixes → Re-scan
  │
  └── Changes app behavior? (any fix that alters functionality)
        │
        └── Yes → Comment on PR: "Please verify with /try-it"
                  → Wait for developer to re-submit via /ship-it
```

### 6.3 Layer 3: Continuous Scanning (Post-Deploy)

**When:** On schedule (cron) or on push to main
**Owner:** Security team / AuditGithub platform
**Scope:** Ongoing vulnerability monitoring

| Action | Mechanism | Response |
|--------|-----------|----------|
| Scan repo | AuditGithub scans on push + daily cron | Findings stored in database |
| Notify | GitHub Issues created per finding (labeled `auditgithub` + severity) | Persistent visibility |
| Remediate | `/resume-it` reads findings via API, applies `ai_remediation_diff` | Automated fix |
| Verify | Developer runs `/try-it` if behavior changed | User confirmation |
| Close | AuditGithub rescans after push, auto-closes resolved Issues | Audit trail |

**Integration protocol:**

```
AuditGithub → GitHub:
  POST GitHub Issue per finding
  Labels: auditgithub, severity:{level}, type:{category}
  Body: finding_id, file, line, AI recommendation, confidence

/resume-it → AuditGithub API:
  GET /findings/paginated?repo_name={repo}&status=open
  GET /findings/{id}  (includes ai_remediation_diff)
  PATCH /findings/{id}/status  (mark resolved after fix)
```

### 6.4 Scanning Coverage Matrix

| Vulnerability Class | Layer 1 (Pre-Push) | Layer 2 (PR Scan) | Layer 3 (Continuous) |
|--------------------|--------------------|-------------------|---------------------|
| Known dependency CVEs | Yes | Yes (redundant, catches drift) | Yes |
| Hardcoded secrets | No | Yes | Yes |
| OWASP patterns | No | Yes | Yes |
| IaC misconfig | No | Yes | No |
| Container vulns | No | Yes | Yes |
| License violations | No | Yes | No |
| Zero-day CVEs | No | No | Yes (as advisories publish) |
| Business logic flaws | No | No | No (requires manual review) |

---

## 7. Environment Promotion Strategy

### 7.1 Environments

| Environment | Purpose | Deployed By | Approval Required |
|-------------|---------|-------------|-------------------|
| **Dev** | Integration testing, developer verification | GitHub Actions (auto on PR scan pass) | No |
| **Staging** | Pre-production validation (optional, activated per-app) | GitHub Actions (manual trigger) | DevOps approval |
| **Production** | Live, user-facing | GitHub Actions (on merge to main) | DevOps approval + environment protection |

Default flow is **dev → production**. Staging is available when activated in `.ship-it.yml`:

```yaml
deployment:
  environments:
    dev: dev
    staging: staging        # Optional: uncomment to enable
    production: production
```

### 7.2 Promotion Gates

#### Dev Gate (Automated)

All of the following must pass before code reaches dev:

- [ ] Docker images build successfully
- [ ] Unit tests pass
- [ ] Security scan: no critical or high findings (or all auto-remediated)
- [ ] IaC validation passes (if Terraform present)
- [ ] Container scan: no critical CVEs in base images

#### Production Gate (DevOps Approval)

All of the following must pass before code reaches production:

- [ ] Dev deployment healthy for minimum 30 minutes
- [ ] Developer has verified in dev (PR comment or /try-it confirmation)
- [ ] No open critical/high security findings on the repo
- [ ] Terraform plan reviewed (if infrastructure changes)
- [ ] DevOps team member approves via GitHub environment protection rule
- [ ] Compliance tags validated (if applicable, see Section 10)

#### Staging Gate (When Enabled)

- [ ] All dev gate checks pass
- [ ] Performance baseline established (response time, error rate)
- [ ] Load test passes (if configured)
- [ ] DevOps approval

### 7.3 Promotion Flow

```
PR created (by /ship-it)
  │
  ▼
Build + Security Scan (automated)
  │
  ├── Findings? → Auto-remediate → Re-scan → Loop until clean
  │                                   │
  │                         Can't auto-fix? → DevOps manual fix
  │                                             │
  │                         Behavior changed? → Notify developer
  │                                             → /try-it verify
  │                                             → /ship-it resubmit
  │
  ▼
Deploy to Dev (automated)
  │
  ▼
Developer verifies in Dev
  │
  ├── "Works as expected" → Merge PR to main
  │
  └── "Something's wrong" → /resume-it to fix → /ship-it resubmit → re-scan
  │
  ▼
Merge to main triggers production pipeline
  │
  ▼
Production preflight (stricter scans)
  │
  ▼
DevOps approval (GitHub environment protection)
  │
  ▼
Deploy to Production (rolling)
  │
  ▼
Production smoke tests
  │
  ├── Pass → Notify developer: "Your app is live"
  │
  └── Fail → Auto-rollback (Section 9)
```

---

## 8. Infrastructure Provisioning (Terraform)

### 8.1 What /make-it Generates

`/make-it` generates Terraform as a **DevOps handoff artifact**. The developer never sees or applies it.

```
infrastructure/
├── main.tf              # Cloud resources the app needs
├── variables.tf         # Configurable values (names, SKUs, tags)
├── outputs.tf           # Values the app needs (connection strings, URLs)
├── versions.tf          # Provider version constraints
├── backend.tf           # State backend (S3 + DynamoDB for AWS)
└── environments/
    ├── dev.tfvars       # Dev-specific values
    └── prod.tfvars      # Prod-specific values
```

### 8.2 Proposed Terraform Pipeline

**Repository:** Each app repo contains its `infrastructure/` directory.
**State:** S3 bucket per environment (`{org}-terraform-state/{app-slug}/{env}`)
**Execution:** GitHub Actions job in the shared workflow.

```
PR created with infrastructure/ changes
  │
  ▼
terraform fmt -check        (fail PR if unformatted)
terraform validate          (fail PR if invalid)
terraform plan              (post plan output as PR comment)
tflint                      (lint for best practices)
  │
  ▼
DevOps reviews plan in PR comment
  │
  ├── Approve → Merge triggers apply
  │
  └── Request changes → Developer or DevOps adjusts
  │
  ▼
On merge to main:
  terraform apply -var-file=environments/dev.tfvars     (auto)
  terraform apply -var-file=environments/prod.tfvars    (requires approval)
  │
  ▼
Outputs (connection strings, URLs) → injected into ECS task definition
```

### 8.3 Terraform Ownership

| Action | Owner | When |
|--------|-------|------|
| Generate Terraform files | /make-it (automated) | During app build |
| Review Terraform plan | DevOps engineer | On PR |
| Apply to dev | GitHub Actions (automated) | On merge |
| Apply to production | GitHub Actions (with approval) | After dev verification |
| State management | DevOps team | Ongoing |
| Module maintenance | DevOps team | As needed |
| Drift detection | DevOps team (scheduled plan) | Weekly |

### 8.4 First Deploy Bootstrap

For new applications, the first deployment requires a one-time bootstrap:

1. DevOps fills in the `infra` section of `.ship-it.yml`:
   ```yaml
   infra:
     provider: aws
     aws:
       region: us-east-1
       account_id: "123456789012"
       ecr_registry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
       ecs:
         cluster_name: "apps-cluster"
   ```
2. DevOps creates ECR repositories (or the workflow creates them on first push)
3. DevOps configures GitHub environment secrets
4. DevOps reviews and applies the initial Terraform plan
5. Subsequent deploys are fully automated

---

## 9. Rollback Strategy

### 9.1 Automated Rollback

If production smoke tests fail after deployment, the pipeline automatically rolls back.

**ECS Rolling Deployment (default):**
```
Deploy new task definition revision
  → ECS drains old tasks, starts new tasks
  → Health check fails on new tasks?
    → ECS stops rolling update
    → Old tasks remain running
    → Pipeline marks deployment as failed
    → Notify DevOps + developer
```

**ECS Blue/Green (optional, for critical apps):**
```
Deploy to green target group
  → Run smoke tests against green
  → Pass? → Swap ALB listener to green → Drain blue
  → Fail? → Delete green → Blue remains live → Notify
```

### 9.2 Manual Rollback

DevOps can trigger a manual rollback at any time:

```bash
# Roll back to previous task definition revision
aws ecs update-service \
  --cluster {app-slug}-cluster \
  --service {app-slug}-backend-svc \
  --task-definition {app-slug}-backend:{previous-revision}

# Or via GitHub Actions: re-run the last successful deploy job
gh run rerun {run-id} --job deploy-prod
```

### 9.3 Database Rollback

Alembic supports downgrade migrations:

```bash
# Roll back one migration
alembic downgrade -1

# Roll back to specific revision
alembic downgrade {revision_id}
```

**Policy:** Migrations that drop columns or tables must include a downgrade path. The shared workflow validates this by checking that every migration has both `upgrade()` and `downgrade()` functions.

### 9.4 Rollback Decision Matrix

| Symptom | Detection | Action | Owner |
|---------|-----------|--------|-------|
| Health check fails after deploy | Automated (ECS) | Auto-rollback (ECS stops rollout) | Automated |
| Smoke test fails after deploy | Automated (workflow) | Trigger ECS rollback + notify | Automated |
| Error rate spike in production | CloudWatch alarm | Alert DevOps → manual rollback | DevOps |
| Developer reports broken functionality | Manual | DevOps triggers rollback | DevOps |
| Security vulnerability in deployed code | AuditGithub | /resume-it auto-fix → /ship-it redeploy | Automated + Developer verify |

---

## 10. Compliance Tagging (Optional)

For applications subject to regulatory requirements, compliance tags can be added to `.ship-it.yml`:

```yaml
deployment:
  compliance:
    - soc2
    - hipaa
```

Or as GitHub labels on the PR: `compliance:soc2`, `compliance:hipaa`.

### 10.1 What Compliance Tags Activate

| Tag | Additional Gate | Evidence |
|-----|----------------|----------|
| `soc2` | Change management approval trail, access review | PR approval history, scan results archived to S3 |
| `hipaa` | PHI data flow validation, encryption-at-rest check | Terraform plan confirms RDS encryption, ECS task confirms no PHI in logs |
| `pci` | Network segmentation validation, key rotation check | VPC configuration review, Secrets Manager rotation enabled |
| `fedramp` | FIPS 140-2 compliance check, US region enforcement | Terraform plan confirms us-gov region, FIPS endpoints |

### 10.2 Compliance Evidence Storage

When compliance tags are present, the shared workflow archives evidence:

```
s3://{org}-compliance-evidence/{app-slug}/{deploy-date}/
  ├── scan-results.json        # Full security scan output
  ├── terraform-plan.txt       # Infrastructure plan
  ├── pr-approval.json         # Who approved, when
  ├── deploy-manifest.json     # Image SHAs, task definition, config
  └── smoke-test-results.json  # Post-deploy verification
```

---

## 11. Monitoring and Alerting

### 11.1 Application Monitoring

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| Health check failures | ECS health check | 3 consecutive failures |
| HTTP 5xx rate | ALB metrics | >1% of requests over 5 minutes |
| Response latency (p99) | ALB metrics | >5s over 5 minutes |
| Container restarts | ECS events | >3 restarts in 10 minutes |
| CPU utilization | ECS metrics | >80% sustained for 10 minutes |
| Memory utilization | ECS metrics | >85% sustained for 10 minutes |

### 11.2 Pipeline Monitoring

| Event | Notification | Channel |
|-------|-------------|---------|
| Build failure | PR comment + DevOps channel | GitHub + Slack/Teams |
| Security scan finds critical | PR comment + DevOps channel | GitHub + Slack/Teams |
| Auto-remediation applied | PR comment (developer) | GitHub |
| Deploy to dev succeeded | PR comment (developer) | GitHub |
| Deploy to prod succeeded | PR comment (developer) + DevOps channel | GitHub + Slack/Teams |
| Deploy to prod failed | DevOps channel (urgent) | Slack/Teams + PagerDuty |
| Rollback triggered | DevOps channel (urgent) | Slack/Teams + PagerDuty |

---

## 12. Communication Contracts

### 12.1 Pipeline → Developer (PR Comments, Plain Language)

**On PR scan start:**
> "Your app is being reviewed by our automation. You don't need to do anything -- we'll let you know when it's ready."

**On auto-remediation (no behavior change):**
> "We updated a few dependencies to keep your app secure. No changes to how it works."

**On auto-remediation (behavior may change):**
> "We made some updates to keep your app secure. Please check that everything still works by running `/try-it` in your project."

**On deploy to dev:**
> "All checks passed! Your app is deployed to the dev environment. Test it at: https://{app-slug}-dev.example.com
>
> When you've verified everything works, merge this PR to deploy to production."

**On deploy to production:**
> "Your app is live! https://{app-slug}.example.com"

**On deploy failure:**
> "We ran into an issue deploying your app. The team is looking into it -- you don't need to do anything."

### 12.2 Pipeline → DevOps (Internal Channels, Technical Detail)

- Full scan results with finding IDs, severities, and remediation status
- Terraform plan diffs for infrastructure changes
- Items requiring human judgment (flagged for manual review)
- Deployment approval requests with risk assessment
- Rollback notifications with root cause context

### 12.3 Developer → Pipeline (Implicit Signals)

| Developer Action | Signal to Pipeline |
|-----------------|-------------------|
| `/ship-it` creates PR | "Code is ready for review" |
| `/ship-it` after /try-it verify | "I've verified the remediation works" |
| Merge PR to main | "Deploy to production" |
| `/ship-it save` | "Work in progress, don't deploy" |

---

## 13. What the Pipeline Does NOT Do

- **Modify application behavior or business logic** -- fixes are limited to dependencies, config, and infrastructure
- **Deploy without passing all security gates** -- no bypass mechanism
- **Deploy to production without DevOps approval** -- GitHub environment protection enforced
- **Communicate in technical jargon to the developer** -- all developer-facing messages are plain language
- **Skip scanning for any reason** -- even if the developer says "it's urgent"
- **Store secrets in code** -- all secrets flow through Secrets Manager

---

## 14. Validation (harness-it)

The [harness-it](https://github.com/sealmindset/harness-it) repository validates this entire pipeline using LocalStack (simulated AWS):

| Test Suite | What It Validates |
|-----------|-------------------|
| `test-config-loader.sh` | /ship-it config merge logic (4-layer priority) |
| `test-workflow-gen.sh` | Generated workflow has correct ECR/ECS/deploy steps |
| `smoke-test-e2e.sh` | LocalStack infrastructure + deploy scripts work |
| `full-pipeline-e2e.sh` | End-to-end: scaffold → config → workflow → deploy → verify (42 tests) |

Before any change to the shared workflow goes live, it must pass all harness-it tests against LocalStack. This includes:
- Docker image builds succeed
- ECR push simulation works
- ECS task definitions are valid
- Database migrations run cleanly
- App starts and passes health checks
- Auth flow works end-to-end
- API endpoints return expected responses

---

## 15. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

- [ ] Create `{org}/shared-workflows` repository
- [ ] Build shared reusable workflow (Jobs 1-2: build + security scan)
- [ ] Configure GitHub environment protection rules (dev, production)
- [ ] Set up organization-level secrets (AWS credentials, scanner API keys)
- [ ] Validate with harness-it against LocalStack

### Phase 2: Deployment (Week 3-4)

- [ ] Add deploy jobs to shared workflow (Jobs 4-5: dev + production)
- [ ] Build auto-remediation job (Job 3)
- [ ] Set up CloudWatch alarms and notification channels
- [ ] Configure Terraform pipeline (plan on PR, apply on merge)
- [ ] Deploy DeliverIt as first production app through the pipeline

### Phase 3: Continuous Scanning (Week 5-6)

- [ ] Configure AuditGithub (or equivalent) for deployed repos
- [ ] Validate /resume-it integration with scanner API
- [ ] Set up compliance evidence archival (if applicable)
- [ ] Document runbooks for manual remediation and rollback

### Phase 4: Hardening (Week 7-8)

- [ ] Add staging environment support to shared workflow
- [ ] Implement blue/green deployment option for critical apps
- [ ] Add performance baseline tests to promotion gates
- [ ] Conduct tabletop exercise: simulated security incident → rollback → remediation
- [ ] DevOps team signs off on production readiness

---

## 16. Open Questions

1. **Shared workflow repo location** -- Should this live in `{org}/shared-workflows` or `{org}/.github`?
2. **ECR repo creation** -- Should the workflow auto-create ECR repos on first deploy, or require DevOps to pre-create them?
3. **Notification channel** -- Slack, Teams, or both for DevOps alerts?
4. **Scanner selection** -- Confirm tooling: gitleaks vs trufflehog, trivy vs grype, semgrep vs CodeQL?
5. **Terraform state locking** -- DynamoDB table for state locking, or S3-native?
6. **Approval timeout** -- How long should a production deployment wait for approval before expiring?

---

## Appendix A: .ship-it.yml Full Schema

```yaml
# APP -- What is being deployed (auto-populated by /make-it)
app:
  name: "DeliverIt"
  slug: "deliverit"
  stack: "fastapi-nextjs"
  description: "Task tracker with readiness checklists and Jira sync"
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
  provider: aws                    # aws | azure | ""
  aws:
    region: us-east-1
    account_id: "123456789012"
    ecr_registry: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
    ecs:
      cluster_name: "apps-cluster"
    dns:
      domain: "apps.example.com"   # Optional: enables DNS pre-check in checklist

# DEPLOYMENT -- How the pipeline behaves
deployment:
  environments:
    dev: dev
    # staging: staging             # Uncomment to enable staging
    production: production
  reviewers:
    - devops-lead
  strategy: rolling                # rolling | blue-green
  compliance: []                   # Optional: [soc2, hipaa, pci, fedramp]
  prerequisites: []                # Optional: custom go-live checklist items
```

### Config Merge Priority (highest wins)

1. `.ship-it.yml` values (DevOps overrides everything)
2. `app-context.json` values (from /make-it)
3. Auto-detected values (stack detection from package.json, requirements.txt, etc.)
4. Sensible defaults

---

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| `/make-it` | Claude Code skill that builds applications from plain English |
| `/ship-it` | Claude Code skill that creates PRs and hands off to CI/CD |
| `/try-it` | Claude Code skill that starts the app locally for developer verification |
| `/resume-it` | Claude Code skill that iterates on existing apps (features, bug fixes, security remediation) |
| Caller workflow | Per-app GitHub Actions workflow that calls the shared reusable workflow |
| Shared workflow | Organization-level reusable GitHub Actions workflow owned by DevOps |
| harness-it | Test harness that validates the pipeline using LocalStack (simulated AWS) |
| AuditGithub | Security scanning platform (custom, FastAPI + PostgreSQL + 20+ scanners) |
| DevOps BOT | CI/CD automation that scans PRs and auto-remediates (to be built) |
| Intent | Classification of deployment scope: experiment, shareable, or prod-ready |
