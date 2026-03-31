# Deployment Profile Architecture

How /ship-it, /resume-it, and /argo-it work together to make any app deployable on any platform — without the app creator knowing anything about the platform.

---

## The App Creator's World vs. The Machine's World

The app creator (vibe coder) lives in a simple world:

```
1. "I built my app with /make-it"
2. "I tested it with /try-it"
3. "I'm ready to go live"  →  /ship-it
4. "Done! The DevOps team will take it from here."
```

They never see, understand, or interact with deployment profiles, code patterns, Terraform, Kubernetes, or cloud-specific configuration. **Every message they receive is in plain English, describing what their app DOES, not how the code WORKS.**

Behind the scenes, this is what actually happens:

```
/make-it builds UNIVERSAL apps (works anywhere, no cloud assumptions)
                    │
                    │  Profile applied at DEPLOYMENT TIME, not build time
                    ▼
/ship-it            reads the DevOps team's profile
                    │  silently transforms the app to meet platform requirements
                    │  tells the app creator: "Preparing your app for deployment..."
                    ▼
                    App is platform-ready. PR created for DevOps review.
```

The app works locally without any profile. Profiles are additive — they layer platform requirements on top of a working app. The universal app is never broken by profile application.

---

## Communication Rules (MANDATORY)

Every skill that touches deployment profiles MUST follow these rules when talking to the app creator:

### Never say these words to the app creator
`profile`, `pattern`, `token`, `managed identity`, `credential`, `Key Vault`, `Secrets Manager`, `Terraform`, `SDK`, `ingress`, `namespace`, `YAML`, `manifest`, `Kubernetes`, `K8s`, `container registry`, `ACR`, `ECR`, `Kustomize`, `Argo`, `Flux`, `GitOps`, `CIDR`, `VNet`, `subnet`, `DNS zone`, `SSL`, `TLS`, `certificate issuer`, `ESO`, `RBAC` (in infrastructure context), `IAM`, `idempotent`, `rollback`, `dependency graph`

### Instead, say
| Technical concept | Plain English for app creator |
|---|---|
| Applying deployment profile | "Preparing your app for deployment" |
| Token-refresh pattern | "Switching to your company's secure database login" |
| Key Vault / Secrets Manager | "Moving sensitive settings to your company's secure vault" |
| Health check endpoint | "Adding a way for the system to check your app is healthy" |
| Managed identity | "Your company's secure login system" |
| Kubernetes manifests | "Deployment setup files" |
| Terraform | "Infrastructure setup" |
| Pattern failed | "One of the updates didn't work" |
| Rollback | "I've undone that change — your app still works" |
| Profile not found | "Your DevOps team hasn't set up a deployment configuration yet" |
| Profile validation error | "There's a setup issue I need your DevOps team to fix" |
| Ingress / networking | "How people will access your app" |
| Container registry | "Where your app is stored for deployment" |
| CI/CD pipeline | "The automated process that checks and deploys your app" |

### Progress updates
Keep the app creator informed with simple status messages:
```
"Preparing your app for deployment..."
"Making 3 updates to meet your company's requirements..."
"Update 1 of 3: Switching to secure database login... done"
"Update 2 of 3: Moving settings to secure vault... done"
"Update 3 of 3: Adding health monitoring... done"
"Checking that everything still works... all good!"
"Creating a review request for your DevOps team..."
"Done! Review request #47 sent. The DevOps team will take it from here."
```

### Error messages
```
GOOD: "One of the updates didn't work, but the other two are fine.
       I've added a note for your DevOps team."

BAD:  "The token-refresh-db pattern failed because @azure/identity
       threw a DefaultAzureCredential authentication error."

GOOD: "There's a setup issue I need your DevOps team to fix before
       we can go live. You can tell them: 'The deployment profile
       needs the container registry URL.'"

BAD:  "Profile validation failed: registry.url is required."
```

---

## Architecture Overview

> **This section is for skill developers.** The app creator never sees any of this.

```
┌─────────────────────────────────────────────────────────────────┐
│                     DevOps / Platform Team                       │
│                                                                  │
│  Writes profiles:     ~/.claude/devops-profiles/<name>.yml       │
│  Publishes via:       Central repo + install script              │
│  Maintains patterns:  Code transformation recipes                │
│                                                                  │
│  (Technical audience — sees YAML, pattern names, config)         │
└──────────────────────────────┬───────────────────────────────────┘
                               │
                               │  Profile defines WHAT the platform needs
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Profile Engine                            │
│                                                                  │
│  1. Load profile (project > user > central)                      │
│  2. Resolve placeholders ({app_slug}, {env}, etc.)               │
│  3. Validate required fields                                     │
│  4. Build pattern execution plan (dependency-ordered)            │
│  5. Hand off to the requesting skill                             │
│                                                                  │
│  (Invisible — runs silently, never surfaces to app creator)      │
└──────┬──────────────────┬───────────────────┬────────────────────┘
       │                  │                   │
       ▼                  ▼                   ▼
   /ship-it          /resume-it          /argo-it
   (orchestrate)     (transform code)    (generate manifests)
       │                  │                   │
       ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                     App Creator (Vibe Coder)                     │
│                                                                  │
│  Sees only: "Preparing your app... done! Review request sent."   │
│                                                                  │
│  (Non-technical — sees plain English, no jargon, no config)      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Skill Responsibilities

### /ship-it — Orchestrator

Ship-it is the entry point. When the app creator runs `/ship-it` (or `/ship-it <profile>`):

```
/ship-it azure-sleepnumber
       │
       ├─ 1. Load & validate profile
       │
       ├─ 2. Compare profile requirements vs current app state
       │     - Which patterns are already applied?
       │     - Which patterns are missing?
       │     - Any conflicts? (e.g., app has static password, profile needs token-refresh)
       │
       ├─ 3. If patterns need applying → delegate to /resume-it
       │     Tell app creator: "I need to make 3 updates to prepare
       │      your app. I'll handle it — you'll check it after."
       │
       ├─ 4. If K8s manifests needed → delegate to /argo-it
       │     Pass profile's kubernetes/ingress/registry config
       │
       ├─ 5. Run pre-push self-review (existing 6 checks)
       │
       ├─ 6. Create PR with profile-aware metadata
       │     - PR description includes which profile was applied
       │     - Labels include platform target
       │
       └─ 7. Post-push CI monitoring (existing behavior)
```

**New ship-it responsibilities:**
- Profile loading and validation
- Gap analysis (what's applied vs what's needed)
- Orchestrating resume-it and argo-it
- Recording `deployment.profile` in app-context.json

**NOT ship-it's job:**
- Applying code changes (that's resume-it)
- Generating K8s manifests (that's argo-it)

### /resume-it — Code Transformer

Resume-it gains a new capability: applying named code transformation patterns from a profile.

```
/resume-it receives pattern list from /ship-it
       │
       ├─ 1. Read pattern definitions (what to change, where, how)
       │
       ├─ 2. Check prerequisites per pattern
       │     - token-refresh-db: Is there a database.service.ts or equivalent?
       │     - keyvault-secrets: Is there Terraform with secret references?
       │     - managed-identity-tf: Is there a Terraform directory?
       │
       ├─ 3. Apply patterns in dependency order
       │     ┌────────────────────┐
       │     │ managed-identity-tf │ ← No dependencies
       │     └────────┬───────────┘
       │              ▼
       │     ┌────────────────────┐
       │     │ token-refresh-db    │ ← Depends on identity existing
       │     └────────┬───────────┘
       │              ▼
       │     ┌────────────────────┐
       │     │ keyvault-secrets    │ ← Depends on identity for KV access
       │     └────────┬───────────┘
       │              ▼
       │     ┌────────────────────┐
       │     │ health-check-endpoint│ ← Independent, but apply after DB changes
       │     └────────┬───────────┘
       │              ▼
       │     ┌────────────────────┐
       │     │ structured-logging   │ ← Independent
       │     └─────────────────────┘
       │
       ├─ 4. After each pattern: verify app still starts
       │     (same build-verify as /make-it)
       │
       ├─ 5. If pattern application fails: roll back that pattern,
       │     report to user in plain language, continue with next
       │
       └─ 6. Return results to /ship-it
             { applied: [...], skipped: [...], failed: [...] }
```

**Pattern application is idempotent.** Running the same profile twice doesn't duplicate changes. Each pattern checks "am I already applied?" before making changes.

### /argo-it — Manifest Generator (Profile-Aware)

Argo-it already has `.argo-it.yml` for convention detection. Profiles feed into the same system:

```
/argo-it receives profile from /ship-it
       │
       ├─ 1. Merge profile into convention detection
       │     Priority: existing manifests > .argo-it.yml > profile > defaults
       │
       ├─ 2. Profile provides (if not already detected):
       │     - registry.url → image references
       │     - ingress.controller → IngressRoute vs Ingress vs ALB
       │     - kubernetes.namespace_pattern → namespace
       │     - kubernetes.deploy_branch_pattern → deploy branch
       │     - kubernetes.storage_class → PVC specs
       │     - kubernetes.secret_pattern → ExternalSecret names
       │     - secrets.eso → ExternalSecret manifests (if ESO enabled)
       │
       ├─ 3. Generate manifests (existing behavior, now profile-informed)
       │
       ├─ 4. Generate CI workflow (existing behavior, now profile-informed)
       │     - Use profile's ci.platform (not just GitHub Actions)
       │     - Use profile's ci.reusable_workflow if set
       │     - Include profile's ci.required_checks
       │
       └─ 5. Generate ONBOARDING-K8S.md (existing behavior, profile-aware)
             - Include profile-specific setup steps
             - Reference profile's secret store for secret creation
```

**Key: argo-it treats the profile as a lower-priority convention source.** If the repo already has manifests with conventions, those win. The profile only fills in gaps.

---

## Data Flow

```
                    ┌─────────────────┐
                    │ devops-profile   │ DevOps authors this
                    │ .yml             │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Profile Engine   │ Load, validate, resolve
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │ app-context │  │ .ship-it   │  │ .argo-it   │
     │ .json       │  │ .yml       │  │ .yml       │
     └──────┬─────┘  └──────┬─────┘  └──────┬─────┘
            │               │               │
            │  Profile fills gaps in these files (never overwrites)
            │               │               │
            ▼               ▼               ▼
     ┌────────────────────────────────────────────┐
     │              /ship-it                       │
     │  Orchestrates: gap analysis, delegation     │
     └────────┬────────────────────┬──────────────┘
              │                    │
              ▼                    ▼
     ┌────────────────┐   ┌────────────────┐
     │  /resume-it     │   │  /argo-it       │
     │  Code transforms│   │  K8s manifests  │
     └────────┬───────┘   └────────┬───────┘
              │                    │
              ▼                    ▼
     ┌────────────────────────────────────────────┐
     │           App is platform-ready             │
     │  Code + Terraform + K8s manifests + CI      │
     └─────────────────────────────────────────────┘
```

---

## Pattern Dependency Graph

Patterns declare their dependencies. Resume-it topologically sorts them before execution.

```yaml
# Internal pattern registry (in resume-it, not in profile)
patterns:
  managed-identity-tf:
    depends_on: []
    modifies: [terraform/]
    verifies: "terraform validate"

  token-refresh-db:
    depends_on: [managed-identity-tf]
    modifies: [src/database/*, package.json]
    verifies: "app starts, DB connection succeeds"

  keyvault-secrets:
    depends_on: [managed-identity-tf]
    modifies: [terraform/]
    verifies: "terraform validate, no plaintext connection strings in env vars"

  container-app-tf:
    depends_on: [managed-identity-tf, keyvault-secrets]
    modifies: [terraform/]
    verifies: "terraform validate"

  ecs-fargate-tf:
    depends_on: [managed-identity-tf, keyvault-secrets]
    modifies: [terraform/]
    verifies: "terraform validate"

  health-check-endpoint:
    depends_on: []
    modifies: [src/health/*, src/app.*]
    verifies: "GET /healthz returns 200"

  structured-logging:
    depends_on: []
    modifies: [src/**/*.ts, src/**/*.py]
    verifies: "app starts, logs are JSON"

  correlation-id:
    depends_on: [structured-logging]
    modifies: [src/middleware/*]
    verifies: "request includes X-Request-ID in response"

  split-ingress:
    depends_on: []
    modifies: [env/*/]
    verifies: "kustomize build succeeds"
```

---

## Idempotency Detection

Each pattern knows how to check if it's already applied:

| Pattern | "Already applied" signal |
|---------|------------------------|
| `token-refresh-db` | `@azure/identity` in package.json + token refresh code in DB service |
| `keyvault-secrets` | All connection strings reference Key Vault in Terraform |
| `managed-identity-tf` | `azurerm_user_assigned_identity` resource exists |
| `health-check-endpoint` | `/healthz` route exists and returns 200 |
| `structured-logging` | Logger configured with JSON format |
| `correlation-id` | Middleware sets `X-Request-ID` header |

If already applied, pattern is skipped with `status: already-applied`.

---

## User Experience

The app creator's experience stays dead simple. Note: even the profile name is translated to the `display_name` from the profile. The app creator sees "Sleep Number Azure Platform", not "azure-sleepnumber".

### Happy path
```
App creator: /ship-it

Claude: I found a deployment setup from your DevOps team
        (Sleep Number Azure Platform).

        I need to make 3 updates to prepare your app:
        1. Switching to your company's secure database login
        2. Moving sensitive settings to your company's secure vault
        3. Adding a way for the system to check your app is healthy

        Making these updates now...

        Update 1 of 3: Secure database login... done
        Update 2 of 3: Secure vault for settings... done
        Update 3 of 3: Health monitoring... done

        Checking that everything still works... all good!

        Creating a review request for your DevOps team...

        Your app is ready! Review request #47 has been sent.
        The DevOps team will take it from here.
```

### When there are multiple profiles
```
App creator: /ship-it

Claude: Your DevOps team has set up two deployment options:
        1. Sleep Number Azure Platform
        2. Sleep Number On-Prem Platform

        Which one should I use?

App creator: 1

Claude: Great! Preparing your app for the Sleep Number Azure Platform...
```

### When the profile was already applied
```
App creator: /ship-it

Claude: Your app is already set up for the Sleep Number Azure Platform.
        No additional updates needed.

        Creating a review request with your latest changes...
```

### When something goes wrong
```
App creator: /ship-it

Claude: I'm preparing your app for deployment.

        Update 1 of 3: Secure database login... done
        Update 2 of 3: Secure vault for settings... I ran into an issue.
                        I've undone that change — your app still works.
        Update 3 of 3: Health monitoring... done

        2 out of 3 updates were successful. I've added a note about
        the vault setup for your DevOps team in the review request.

        Review request #47 has been sent. The DevOps team will fix
        the remaining item and let you know.
```

### What the app creator NEVER sees
- Profile YAML or file names
- Pattern names (token-refresh-db, keyvault-secrets, etc.)
- Dependency graphs or execution order
- Terraform, Kubernetes, or cloud-specific details
- SDK imports, code snippets, or file paths
- Error codes, stack traces, or technical error messages
- The word "profile" — say "deployment setup" or "deployment configuration" instead

---

## Failure Modes

Each failure has two messages — one for the app creator (plain English) and one for DevOps (technical, logged in the PR or commit message).

| Failure | App creator sees | DevOps sees (in PR/logs) |
|---------|-----------------|--------------------------|
| Profile not found | "Your DevOps team hasn't set up a deployment configuration yet. Ask them to set one up, or I can ship without one." | N/A |
| Multiple profiles | "Your DevOps team has set up a few deployment options: [list by display_name]. Which one should I use?" | N/A |
| Profile validation fails | "There's a setup issue I need your DevOps team to fix before we can go live. You can tell them: 'The deployment configuration needs updating.'" | "Profile validation failed: `registry.url` required. Profile: `azure-sleepnumber` v1" |
| Pattern fails to apply | "One of the updates didn't work, but the others are fine. I've added a note for your DevOps team." | "Pattern `token-refresh-db` failed: @azure/identity AuthenticationError. Rolled back." |
| App breaks after pattern | "Something went wrong with the updates. I've undone them all — your app still works. I'll let your DevOps team know." | "Build-verify failed after `keyvault-secrets`: exit code 1. All patterns rolled back." |
| Conflict with existing code | "Your app already has health monitoring set up, but it's a little different from what your company expects. Should I update it?" | "Existing /health conflicts with profile-required /healthz. Awaiting user confirmation." |

---

## What Changes in Each Skill

### /ship-it (new capabilities)

```
BEFORE:  /ship-it
         - Reads .ship-it.yml
         - Runs 6 pre-push checks
         - Creates PR

AFTER:   /ship-it [profile-name]
         - Loads profile (if specified)
         - Compares profile requirements vs app state
         - Delegates to /resume-it for code changes
         - Delegates to /argo-it for K8s manifests
         - Runs 6 pre-push checks (unchanged)
         - Creates PR with profile metadata
         - Records deployment.profile in app-context.json
```

### /resume-it (new capabilities)

```
BEFORE:  Standards catch-up scan (build-standards.md)
         Fix bugs, add features, work TODOs

AFTER:   All of the above, PLUS:
         - Named pattern application (from profile)
         - Pattern dependency resolution
         - Idempotency detection
         - Per-pattern rollback
         - Build-verify after each pattern
```

### /argo-it (enhanced convention detection)

```
BEFORE:  Convention priority:
         1. Existing manifests
         2. .argo-it.yml
         3. User answers
         4. Defaults

AFTER:   Convention priority:
         1. Existing manifests
         2. .argo-it.yml
         3. Profile (NEW — fills gaps only)
         4. User answers
         5. Defaults
```

### /make-it (unchanged)

Make-it does NOT change. It still builds universal Docker Compose apps. The profile is a deployment-time concern, not a build-time concern.

### app-context.json (new field)

```json
{
  "deployment": {
    "target": "",
    "containerize": false,
    "prototype_only": false,
    "profile": "",                  // NEW: "azure-sleepnumber"
    "profile_applied_at": "",       // NEW: ISO timestamp
    "patterns_applied": []          // NEW: ["token-refresh-db", "keyvault-secrets", ...]
  }
}
```

---

## Profile Lifecycle

Two tracks running in parallel — the app creator's track and the DevOps track:

```
DevOps track (one-time setup):              App creator track (per app):
─────────────────────────────               ────────────────────────────

1. Write profile for platform               1. Build app with /make-it
   └── YAML config file                        └── Universal app, works anywhere
                                                └── No cloud knowledge needed
2. Publish to central repo
   └── Install script for distribution       2. Test app with /try-it
                                                └── "Looks great!"
3. Install on app creator's machine
   └── DevOps does this, or provides         3. /ship-it
       a one-line install command                └── "Preparing your app..."
                                                 └── "3 updates needed... done!"
                                                 └── "Review request sent!"

                                             4. DevOps reviews the PR
                                                └── App creator waits
                                                └── "Your app is live!"

                                             5. Next time: /ship-it remembers
                                                └── No need to specify again
                                                └── Just /ship-it

                                             6. Profile updates (DevOps publishes)
                                                └── Next /ship-it detects new needs
                                                └── "I need to make 1 more update..."
                                                └── Only applies what's new
```

**Key: the app creator never installs, configures, or knows about profiles.** DevOps sets it up once. The app creator just types `/ship-it`.

---

## What This Solves

### For the app creator
| Problem | How profiles fix it |
|---|---|
| "I don't know anything about Azure/AWS/servers" | You don't need to. Just type `/ship-it`. |
| "My DevOps team keeps asking me to change things" | The profile makes those changes automatically. |
| "My app works locally but not in production" | The profile bridges that gap — same app, platform-ready. |
| "I had to ask a developer to help me deploy" | Not anymore. `/ship-it` handles everything. |

### For the DevOps / Platform team
| Problem (from security review) | How profiles solve it |
|---|---|
| Unsafe database token refresh code | `token-refresh-db` pattern enforces `use_pool_password_function: true` |
| Connection strings in plaintext env vars | `keyvault-secrets` pattern with `rule: all-connection-strings` |
| Personal accounts used for service integrations | `security.service_accounts_required: true` — flagged during pre-push review |
| Azure-specific code leaking into universal scaffold | Code changes happen at deploy time (profile), not build time (scaffold) |
| Every app re-invents platform integration | Patterns written once, applied to every app via profile |
| Inconsistent infrastructure across apps | One profile = one standard, applied uniformly |

### For the organization
| Problem | How profiles fix it |
|---|---|
| Non-technical people can't ship apps to production | Now they can — the profile carries all the technical knowledge |
| Platform requirements change and apps drift | Profile updates are detected automatically on next `/ship-it` |
| Security reviews find the same issues in every app | Patterns encode the fix once — every app gets it right |

---

## Open Questions

1. **Pattern versioning** — When a pattern's implementation changes (e.g., better token refresh approach), should profiles pin pattern versions or always use latest?

2. **Multi-profile** — Can an app have both a "platform" profile (Azure infra) and a "compliance" profile (SOC2 requirements)? Or should these be merged into one?

3. **Profile testing** — Should harness-it validate profiles? (e.g., "apply this profile to the test scaffold and verify it deploys")

4. **Pattern authoring** — Should DevOps teams be able to add custom patterns to a profile, or only use the built-in pattern library?

5. **Dry-run mode** — Should `/ship-it <profile> --dry-run` show what would change without applying? For the app creator, this would look like: "Here's what I'd update — want me to go ahead?"

6. **Onboarding experience** — When a new app creator joins and doesn't have profiles installed, should `/ship-it` detect this and say: "It looks like you're new here. Let me help you get set up — I'll grab your company's deployment settings." Then auto-install?

7. **Profile discovery UX** — Should the app creator be able to ask "where can my app go live?" and get a plain-English list of available platforms from installed profiles?
