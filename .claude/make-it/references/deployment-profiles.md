# Deployment Profiles

Deployment profiles let any app built by /make-it deploy to any organization's platform — Azure, AWS, on-prem, or anything else — without the app creator needing to know how that platform works.

---

## Two Audiences, One System

This document serves two audiences. Everything is designed so they never need to talk to each other:

| | The App Creator (vibe coder) | The Platform Team (DevOps) |
|---|---|---|
| **What they do** | Build apps with /make-it, ship with /ship-it | Write deployment profiles that describe their platform |
| **What they see** | Plain English updates: "Preparing your app for Azure..." | YAML configuration files with technical details |
| **What they know** | Nothing about infrastructure, cloud, or code | Everything about their platform's requirements |
| **What they type** | `/ship-it` or `/ship-it azure` | Nothing — they write the profile once, everyone uses it |

**The app creator NEVER sees:** profile YAML, pattern names, SDK imports, Terraform, Kubernetes manifests, cloud-specific terminology, error codes, or configuration details. Every message is plain English.

---

## What the App Creator Experiences

The app creator's entire interaction with deployment profiles looks like this:

```
You: /ship-it

Claude: Your DevOps team has a deployment setup ready for you.
        I need to make 3 updates to prepare your app:

        1. Switching to your company's secure login for the database
        2. Moving sensitive settings to your company's secure vault
        3. Adding a way for the system to check your app is healthy

        Making these updates now...

        Done! All updates applied and your app still works perfectly.
        Creating a request for your DevOps team to review...

        Your app is ready! A review request (#47) has been sent
        to the DevOps team. They'll take it from here.
```

If something goes wrong:
```
Claude: I ran into an issue with one of the updates.
        The other two updates worked fine.
        I've added a note for your DevOps team so they
        can help with the remaining item.
```

**Rules for communicating with the app creator:**
- NEVER say: "pattern", "profile", "token", "managed identity", "Key Vault", "Terraform", "SDK", "ingress", "namespace", "YAML", "manifest"
- INSTEAD say: "update", "setup", "login", "secure vault", "infrastructure", "your company's system"
- NEVER show file paths, code snippets, or configuration values
- NEVER ask the app creator to make technical decisions — the profile already made them
- If the profile is missing, say: "Your DevOps team hasn't set up a deployment profile yet. Ask them to set one up, or you can ship without one."
- If a pattern fails, say what went wrong in terms of what the app DOES, not what the code IS

---

## Why Profiles Exist

/make-it builds apps that work everywhere: local Docker, any cloud, any server. But every organization's production environment has specific requirements that the app creator shouldn't need to know about:

| What the app creator sees | What's actually happening behind the scenes |
|---|---|
| "Switching to secure database login" | Replacing password auth with cloud-managed identity tokens |
| "Moving settings to secure vault" | Migrating env vars to Key Vault / Secrets Manager / Vault |
| "Setting up where your app will live" | Configuring container registry, ingress, and networking |
| "Adding health monitoring" | Creating /healthz endpoint with dependency checks |

Profiles bridge the gap. The app stays universal until deployment time, then gets silently transformed to meet the target platform. The app creator just types `/ship-it`.

---

## Schema (v1)

> **Audience: DevOps / Platform Engineering only.**
> The app creator never sees, edits, or knows about this file.
> If the app creator asks about it, say: "This is something your DevOps team manages — you don't need to worry about it."

```yaml
# ──────────────────────────────────────────────
# Deployment Profile
# ──────────────────────────────────────────────
# Authored by: DevOps / Platform Engineering team
# Consumed by: /ship-it, /resume-it, /argo-it
# Location:    ~/.claude/devops-profiles/<name>.yml
#              OR <project>/.devops-profile.yml
#
# The app creator (vibe coder) NEVER sees this file.
# All communication with the app creator is plain English.
# ──────────────────────────────────────────────

schema_version: 1
profile_name: ""                    # e.g., "azure-sleepnumber", "aws-fintech", "on-prem-retail"
display_name: ""                    # Human-readable, e.g., "Sleep Number Azure Platform"
cloud: ""                           # azure | aws | gcp | on-prem | hybrid
maintainer: ""                      # Team or email, e.g., "platform-engineering@company.com"
last_updated: ""                    # ISO date, e.g., "2026-03-15"

# ──────────────────────────────────────────────
# Authentication & Identity
# ──────────────────────────────────────────────
auth:
  # How the app authenticates to cloud services (not user auth -- that's in app-context)
  service_identity:
    mechanism: ""                   # managed-identity | iam-role | service-account | static-credential
    provider: ""                    # azure-entra-id | aws-iam | gcp-iam | vault | none

  # Database authentication
  database_auth:
    mechanism: ""                   # token-refresh | iam-auth | static-password | vault-dynamic
    sdk: ""                         # @azure/identity | @aws-sdk/rds-signer | google-auth-library | ""
    token_scope: ""                 # e.g., "https://ossrdbms-aad.database.windows.net/.default"
    refresh_interval_minutes: 45    # Token refresh cadence (only for token-refresh mechanism)

# ──────────────────────────────────────────────
# Secrets Management
# ──────────────────────────────────────────────
secrets:
  store: ""                         # azure-keyvault | aws-secrets-manager | aws-ssm | gcp-secret-manager | vault | k8s-secret | env-file
  access_method: ""                 # managed-identity | iam-role | service-account | sidecar | eso
  rules:
    connection_strings: ""          # always-secret | secret-if-password | env-var
    api_tokens: ""                  # always-secret | env-var
    certificates: ""                # cert-manager | manual | vault-pki

  # External Secrets Operator (if using ESO to sync secrets into K8s)
  eso:
    enabled: false
    store_kind: ""                  # ClusterSecretStore | SecretStore
    store_name: ""                  # e.g., "azure-keyvault-store"
    refresh_interval: "1h"

# ──────────────────────────────────────────────
# Database
# ──────────────────────────────────────────────
database:
  strategy: ""                      # dedicated-managed | shared-managed | in-cluster | external
  server_fqdn_pattern: ""          # e.g., "psql-shared-{env}-scus-01.postgres.database.azure.com"
  database_name_pattern: ""        # e.g., "{app_slug}" or "{app_slug}_{env}"
  username_pattern: ""             # e.g., "{managed_identity_name}" or "{app_slug}_user"
  ssl_mode: "require"              # require | verify-full | prefer | disable
  port: 5432

# ──────────────────────────────────────────────
# Container Registry
# ──────────────────────────────────────────────
registry:
  type: ""                          # acr | ecr | gcr | gar | ghcr | harbor | docker-hub
  url: ""                           # e.g., "{app_slug}devscus01.azurecr.io" or "123456789.dkr.ecr.us-east-1.amazonaws.com"
  auth_method: ""                   # managed-identity | iam-role | docker-config | token
  image_tag_strategy: ""            # env-latest | git-sha | semver
                                    # env-latest: "dev-latest", "prod-latest"
                                    # git-sha: "abc1234"
                                    # semver: "v1.2.3"

# ──────────────────────────────────────────────
# Ingress & Networking
# ──────────────────────────────────────────────
ingress:
  controller: ""                    # nginx | traefik | traefik-ingressroute | alb | istio | cloudflare | none
  hostname_pattern: ""             # e.g., "{app_slug}.{env}.shared-apps.az.sn.corp"
  tls:
    method: ""                      # cert-manager | org-ca | wildcard | manual | none
    issuer: ""                      # e.g., "letsencrypt-prod", "internal-ca"
    secret_pattern: ""             # e.g., "{app_slug}-tls-{env}"
  annotations: {}                   # Key-value pairs added to Ingress/IngressRoute resources

networking:
  private_dns_zones: false          # Whether private DNS is required
  vnet_integration: false           # Whether app needs VNet/VPC integration
  service_mesh: ""                  # istio | linkerd | consul | none
  ip_restrictions: []               # CIDR blocks for ingress (empty = no restriction)

# ──────────────────────────────────────────────
# Kubernetes / Deployment Target
# ──────────────────────────────────────────────
kubernetes:
  namespace_pattern: ""            # e.g., "{app_slug}" or "{team}-{app_slug}"
  storage_class: ""                # e.g., "managed-premium", "gp3", "longhorn"
  deploy_branch_pattern: ""        # e.g., "deploy-{env}" -> "deploy-nonprod", "deploy-prod"
  secret_pattern: ""               # e.g., "{app_slug}-{type}-{env}" -> "myapp-db-dev"
  resource_limits:
    cpu_default: "500m"
    memory_default: "512Mi"
    cpu_max: "2000m"
    memory_max: "2Gi"
  gitops:
    tool: ""                        # argocd | flux | none
    sync_policy: ""                 # auto | manual
    prune: true
    self_heal: true

# ──────────────────────────────────────────────
# CI/CD
# ──────────────────────────────────────────────
ci:
  platform: ""                      # github-actions | gitlab-ci | azure-devops | jenkins
  reusable_workflow: ""            # e.g., ".github/workflows/reusable-deploy.yml@main"
  required_checks: []               # e.g., ["lint", "test", "security-scan", "build"]
  auto_remediate:
    lint: true
    type_errors: true
    dependency_updates: true
    max_cycles: 3

# ──────────────────────────────────────────────
# Security & Compliance
# ──────────────────────────────────────────────
security:
  scanner: ""                       # auditgithub | github-advanced-security | snyk | sonarqube | none
  scanner_api_url: ""              # API endpoint for scanner integration
  required_headers: []              # e.g., ["Strict-Transport-Security", "X-Content-Type-Options"]
  service_accounts_required: true   # Whether machine-to-machine must use service accounts (not personal)

compliance:
  frameworks: []                    # e.g., ["SOC2", "HIPAA", "PCI-DSS"]
  data_classification: ""          # public | internal | confidential | restricted
  audit_logging_required: false

# ──────────────────────────────────────────────
# Terraform / Infrastructure
# ──────────────────────────────────────────────
terraform:
  module_source: ""                # e.g., "github.com/org/terraform-modules"
  state_backend: ""                # azure-storage | s3 | gcs | terraform-cloud | local
  state_config: {}                  # Backend-specific config (bucket name, container, etc.)
  required_tags: {}                 # e.g., {"team": "{team}", "env": "{env}", "app": "{app_slug}"}

# ──────────────────────────────────────────────
# Code Transformation Patterns
# ──────────────────────────────────────────────
# These define WHAT needs to change in app code for this platform.
# Each pattern is a named recipe that /resume-it knows how to apply.
# Patterns are applied in dependency order.
#
# Available patterns (extensible -- new patterns added to resume-it):
#   token-refresh-db        - Add SDK, wrap DB connection with token acquisition + refresh
#   keyvault-secrets        - Move connection strings from env to secret store references
#   managed-identity-tf     - Add managed identity resource to Terraform
#   container-app-tf        - Generate Azure Container App Terraform
#   ecs-fargate-tf          - Generate AWS ECS Fargate Terraform
#   cloud-run-tf            - Generate GCP Cloud Run Terraform
#   split-ingress           - Generate split frontend/backend ingress rules
#   health-check-endpoint   - Add /healthz with dependency checks (DB, cache, etc.)
#   structured-logging      - Replace console.log with structured JSON logger
#   correlation-id          - Add request correlation ID middleware
#
# Each pattern is self-contained: it knows what files to create/modify,
# what dependencies to add, and how to verify the change worked.
# ──────────────────────────────────────────────
patterns:
  - name: ""                        # Pattern identifier (from list above or custom)
    enabled: true                   # Can be disabled per-profile
    config: {}                      # Pattern-specific configuration (varies by pattern)

# Example patterns for Azure + Entra ID:
#
# patterns:
#   - name: token-refresh-db
#     enabled: true
#     config:
#       sdk: "@azure/identity"
#       credential_class: "DefaultAzureCredential"
#       token_scope: "https://ossrdbms-aad.database.windows.net/.default"
#       refresh_minutes: 45
#       use_pool_password_function: true    # Use pg Pool password() function, not mutation
#
#   - name: keyvault-secrets
#     enabled: true
#     config:
#       rule: all-connection-strings        # Even passwordless URLs go in Key Vault
#       terraform_integration: true         # Generate azurerm_key_vault_secret resources
#
#   - name: managed-identity-tf
#     enabled: true
#     config:
#       identity_type: user-assigned
#       name_pattern: "id-{app_slug}-{env}"
#
#   - name: container-app-tf
#     enabled: true
#     config:
#       environment_name_pattern: "cae-{team}-{env}"
#       min_replicas: 1
#       max_replicas: 3
#
#   - name: health-check-endpoint
#     enabled: true
#     config:
#       path: /healthz
#       check_database: true
#       check_redis: false
#
#   - name: structured-logging
#     enabled: true
#     config:
#       format: json
#       include_correlation_id: true
```

---

## Placeholder Variables

Patterns in profile fields use `{variable}` placeholders resolved at apply time:

| Variable | Source | Example |
|----------|--------|---------|
| `{app_slug}` | app-context.json → project_name (slugified) | `capacity-planner` |
| `{app_name}` | app-context.json → project_name | `Capacity Planner` |
| `{env}` | Target environment | `dev`, `prod` |
| `{team}` | Profile or user input | `platform-eng` |
| `{managed_identity_name}` | Terraform output or profile pattern | `id-capacity-planner-dev` |
| `{namespace}` | kubernetes.namespace_pattern resolved | `capacity-planner` |
| `{deploy_branch}` | kubernetes.deploy_branch_pattern resolved | `deploy-nonprod` |

---

## Profile Locations & Precedence

> **Audience: DevOps / Platform Engineering only.**

Profiles are loaded in this order (first match wins):

| Priority | Location | Who manages it | Use case |
|----------|----------|---------------|----------|
| 1 | `<project>/.devops-profile.yml` | DevOps for this specific app | App-specific overrides |
| 2 | `~/.claude/devops-profiles/<name>.yml` | DevOps team (installed) | Org-wide defaults |
| 3 | Central repo (fetched on demand) | Platform Engineering | Source of truth |

**Install flow (DevOps distributes to app creators):**
```bash
# DevOps publishes profiles to a central repo
# App creators install via script (similar to make-it's install.sh)
curl -sL https://raw.githubusercontent.com/org/devops-profiles/main/install.sh | bash

# Or DevOps copies it to the app creator's machine:
cp azure-sleepnumber.yml ~/.claude/devops-profiles/
```

The app creator doesn't need to understand what this file is. If they ask, say: "Your DevOps team set this up so your app can go live on their platform. You don't need to change anything."

---

## Profile Discovery

When the app creator runs `/ship-it <profile-name>`:

1. Check `<project>/.devops-profile.yml` — if exists, use it (ignore `<profile-name>`)
2. Check `~/.claude/devops-profiles/<profile-name>.yml`
3. If not found, list available profiles in plain language and ask the app creator to choose:
   > "I found these deployment options set up by your DevOps team: **Azure Platform** and **AWS Platform**. Which one should I use?"

When the app creator runs `/ship-it` (no profile name):

1. Check `<project>/.devops-profile.yml` — if exists, use it
2. Check app-context.json `deployment.profile` field — if set, load that profile
3. If no profile found, proceed with universal deployment (current behavior)
4. If multiple profiles found and none previously used, ask:
   > "Your DevOps team has set up a couple of deployment options. Which one should I use?"
   > List profiles by `display_name` only — NEVER show file names or paths

---

## Interaction with Existing Config Files

Profiles do NOT replace existing config files. They complement them:

| File | Purpose | Relationship to profile |
|------|---------|------------------------|
| `app-context.json` | What the app IS (features, stack, roles) | Profile reads this; never writes to it |
| `.ship-it.yml` | Deployment intent + CI config | Profile populates missing fields; .ship-it.yml overrides profile |
| `.argo-it.yml` | K8s conventions | Profile provides defaults; .argo-it.yml overrides profile |
| `.devops-profile.yml` | Platform requirements | The profile itself |
| `.env` / `.env.example` | Local dev config | Profile never touches these |
| `docker-compose.yml` | Local dev orchestration | Profile never touches this |

**Override chain:** `.ship-it.yml` > `.devops-profile.yml` > `app-context.json` > auto-detection > defaults

---

## Validation

Profiles are validated when loaded. Required fields depend on which patterns are enabled:

```
schema_version: REQUIRED (must be 1)
profile_name:   REQUIRED
cloud:          REQUIRED
auth:           REQUIRED if any pattern needs identity
secrets.store:  REQUIRED if keyvault-secrets pattern enabled
registry.url:   REQUIRED if argo-it or ship-it will push images
kubernetes:     REQUIRED if argo-it will generate manifests
```

Validation errors are reported differently depending on who's running the skill:

**If the app creator triggers it (via /ship-it):**
> "There's a setup issue with your company's deployment configuration. I'll need your DevOps team to fix it before we can go live. You can tell them: 'The deployment profile is missing the container registry.'"

**If DevOps is testing the profile directly:**
> "Profile validation failed: `registry.url` is required when argo-it or ship-it will push images."

The skill detects audience by context: if running inside /ship-it from a /make-it-built project with `.make-it-state.md`, assume non-technical user. Otherwise, assume DevOps.

---

## Example: Azure + Entra ID (Sleep Number)

Based on the security review that prompted this design:

```yaml
schema_version: 1
profile_name: azure-sleepnumber
display_name: "Sleep Number Azure Platform"
cloud: azure
maintainer: "cloud-services@sleepnumber.com"
last_updated: "2026-03-31"

auth:
  service_identity:
    mechanism: managed-identity
    provider: azure-entra-id
  database_auth:
    mechanism: token-refresh
    sdk: "@azure/identity"
    token_scope: "https://ossrdbms-aad.database.windows.net/.default"
    refresh_interval_minutes: 45

secrets:
  store: azure-keyvault
  access_method: managed-identity
  rules:
    connection_strings: always-secret
    api_tokens: always-secret
    certificates: manual
  eso:
    enabled: true
    store_kind: ClusterSecretStore
    store_name: azure-keyvault-store
    refresh_interval: 1h

database:
  strategy: shared-managed
  server_fqdn_pattern: "psql-shared-{env}-scus-01.postgres.database.azure.com"
  database_name_pattern: "{app_slug}"
  username_pattern: "{managed_identity_name}"
  ssl_mode: require
  port: 5432

registry:
  type: acr
  url: "{app_slug}devscus01.azurecr.io"
  auth_method: managed-identity
  image_tag_strategy: env-latest

ingress:
  controller: traefik-ingressroute
  hostname_pattern: "{app_slug}.{env}.shared-apps.az.sn.corp"
  tls:
    method: org-ca
    issuer: internal-ca
    secret_pattern: "{app_slug}-tls-{env}"
  annotations: {}

networking:
  private_dns_zones: true
  vnet_integration: true
  service_mesh: none
  ip_restrictions: []

kubernetes:
  namespace_pattern: "{app_slug}"
  storage_class: managed-premium
  deploy_branch_pattern: "deploy-{env}"
  secret_pattern: "{app_slug}-{type}-{env}"
  resource_limits:
    cpu_default: "500m"
    memory_default: "512Mi"
    cpu_max: "2000m"
    memory_max: "2Gi"
  gitops:
    tool: argocd
    sync_policy: auto
    prune: true
    self_heal: true

ci:
  platform: github-actions
  reusable_workflow: ""
  required_checks: ["lint", "test", "security-scan", "build"]
  auto_remediate:
    lint: true
    type_errors: true
    dependency_updates: true
    max_cycles: 3

security:
  scanner: auditgithub
  scanner_api_url: ""
  required_headers:
    - Strict-Transport-Security
    - X-Content-Type-Options
    - X-Frame-Options
  service_accounts_required: true

compliance:
  frameworks: []
  data_classification: internal
  audit_logging_required: true

terraform:
  module_source: ""
  state_backend: azure-storage
  state_config: {}
  required_tags:
    team: "{team}"
    env: "{env}"
    app: "{app_slug}"

patterns:
  - name: token-refresh-db
    enabled: true
    config:
      sdk: "@azure/identity"
      credential_class: DefaultAzureCredential
      token_scope: "https://ossrdbms-aad.database.windows.net/.default"
      refresh_minutes: 45
      use_pool_password_function: true

  - name: keyvault-secrets
    enabled: true
    config:
      rule: all-connection-strings
      terraform_integration: true

  - name: managed-identity-tf
    enabled: true
    config:
      identity_type: user-assigned
      name_pattern: "id-{app_slug}-{env}"

  - name: container-app-tf
    enabled: true
    config:
      environment_name_pattern: "cae-shared-{env}"
      min_replicas: 1
      max_replicas: 3

  - name: health-check-endpoint
    enabled: true
    config:
      path: /healthz
      check_database: true

  - name: structured-logging
    enabled: true
    config:
      format: json
      include_correlation_id: true
```

> **Reminder:** The app creator who built "Capacity Planner" with /make-it sees NONE of this. They type `/ship-it`, see "Preparing your app for the Sleep Number Azure Platform...", and get a review request number. That's their entire experience.

---

## Example: AWS + IAM Roles

```yaml
schema_version: 1
profile_name: aws-fintech
display_name: "FinTech AWS Platform"
cloud: aws
maintainer: "platform@fintech.com"
last_updated: "2026-03-20"

auth:
  service_identity:
    mechanism: iam-role
    provider: aws-iam
  database_auth:
    mechanism: iam-auth
    sdk: "@aws-sdk/rds-signer"
    token_scope: ""
    refresh_interval_minutes: 10    # AWS IAM DB tokens are 15-min, refresh at 10

secrets:
  store: aws-secrets-manager
  access_method: iam-role
  rules:
    connection_strings: always-secret
    api_tokens: always-secret
    certificates: cert-manager
  eso:
    enabled: true
    store_kind: ClusterSecretStore
    store_name: aws-secrets-store
    refresh_interval: 1h

database:
  strategy: dedicated-managed
  server_fqdn_pattern: "{app_slug}-{env}.cluster-xxxx.us-east-1.rds.amazonaws.com"
  database_name_pattern: "{app_slug}"
  username_pattern: "{app_slug}_app"
  ssl_mode: verify-full
  port: 5432

registry:
  type: ecr
  url: "123456789012.dkr.ecr.us-east-1.amazonaws.com"
  auth_method: iam-role
  image_tag_strategy: git-sha

ingress:
  controller: alb
  hostname_pattern: "{app_slug}.{env}.platform.fintech.com"
  tls:
    method: cert-manager
    issuer: letsencrypt-prod
    secret_pattern: "{app_slug}-tls"
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internal

networking:
  private_dns_zones: true
  vnet_integration: true
  service_mesh: istio
  ip_restrictions: ["10.0.0.0/8"]

kubernetes:
  namespace_pattern: "{team}-{app_slug}"
  storage_class: gp3
  deploy_branch_pattern: "deploy-{env}"
  secret_pattern: "{app_slug}-{env}"
  resource_limits:
    cpu_default: "250m"
    memory_default: "256Mi"
    cpu_max: "1000m"
    memory_max: "1Gi"
  gitops:
    tool: argocd
    sync_policy: manual
    prune: false
    self_heal: true

ci:
  platform: github-actions
  reusable_workflow: ".github/workflows/shared-deploy.yml@main"
  required_checks: ["lint", "test", "security-scan", "sast", "build"]
  auto_remediate:
    lint: true
    type_errors: true
    dependency_updates: false        # Requires manual review in regulated env
    max_cycles: 3

security:
  scanner: snyk
  scanner_api_url: "https://api.snyk.io/v1"
  required_headers:
    - Strict-Transport-Security
    - X-Content-Type-Options
    - X-Frame-Options
    - Content-Security-Policy
  service_accounts_required: true

compliance:
  frameworks: ["SOC2", "PCI-DSS"]
  data_classification: confidential
  audit_logging_required: true

terraform:
  module_source: "github.com/fintech/terraform-modules"
  state_backend: s3
  state_config:
    bucket: "fintech-terraform-state"
    region: "us-east-1"
    dynamodb_table: "terraform-locks"
  required_tags:
    team: "{team}"
    env: "{env}"
    app: "{app_slug}"
    compliance: "pci"

patterns:
  - name: token-refresh-db
    enabled: true
    config:
      sdk: "@aws-sdk/rds-signer"
      signer_class: Signer
      region: us-east-1
      refresh_minutes: 10
      use_pool_password_function: true

  - name: keyvault-secrets
    enabled: true
    config:
      rule: all-connection-strings
      terraform_integration: true

  - name: ecs-fargate-tf
    enabled: true
    config:
      cluster_name_pattern: "{team}-{env}"
      min_tasks: 2
      max_tasks: 10

  - name: health-check-endpoint
    enabled: true
    config:
      path: /healthz
      check_database: true
      check_redis: true

  - name: structured-logging
    enabled: true
    config:
      format: json
      include_correlation_id: true

  - name: correlation-id
    enabled: true
    config:
      header: X-Request-ID
      propagate: true
```

> **Reminder:** The app creator sees: "Preparing your app for the FinTech AWS Platform..." — never "ECR", "IAM", "Signer", or "SOC2".

---

## Example: Bare Metal / On-Prem

```yaml
schema_version: 1
profile_name: on-prem-retail
display_name: "Retail On-Prem Platform"
cloud: on-prem
maintainer: "infra@retail.com"
last_updated: "2026-03-10"

auth:
  service_identity:
    mechanism: service-account
    provider: vault
  database_auth:
    mechanism: vault-dynamic
    sdk: ""
    token_scope: ""
    refresh_interval_minutes: 30

secrets:
  store: vault
  access_method: service-account
  rules:
    connection_strings: always-secret
    api_tokens: always-secret
    certificates: vault-pki
  eso:
    enabled: false

database:
  strategy: dedicated-managed
  server_fqdn_pattern: "pg-{app_slug}-{env}.db.internal"
  database_name_pattern: "{app_slug}"
  username_pattern: ""              # Dynamic from Vault
  ssl_mode: verify-full
  port: 5432

registry:
  type: harbor
  url: "harbor.internal:5000"
  auth_method: docker-config
  image_tag_strategy: semver

ingress:
  controller: nginx
  hostname_pattern: "{app_slug}.{env}.apps.internal"
  tls:
    method: org-ca
    issuer: internal-ca
    secret_pattern: "{app_slug}-tls"
  annotations: {}

networking:
  private_dns_zones: false
  vnet_integration: false
  service_mesh: none
  ip_restrictions: ["192.168.0.0/16", "10.0.0.0/8"]

kubernetes:
  namespace_pattern: "{app_slug}"
  storage_class: longhorn
  deploy_branch_pattern: "deploy-{env}"
  secret_pattern: "{app_slug}-secrets"
  resource_limits:
    cpu_default: "500m"
    memory_default: "512Mi"
    cpu_max: "4000m"
    memory_max: "4Gi"
  gitops:
    tool: flux
    sync_policy: auto
    prune: true
    self_heal: true

ci:
  platform: gitlab-ci
  reusable_workflow: ""
  required_checks: ["lint", "test", "build"]
  auto_remediate:
    lint: true
    type_errors: true
    dependency_updates: true
    max_cycles: 3

security:
  scanner: sonarqube
  scanner_api_url: "https://sonar.internal/api"
  required_headers:
    - Strict-Transport-Security
    - X-Content-Type-Options
  service_accounts_required: true

compliance:
  frameworks: []
  data_classification: internal
  audit_logging_required: false

terraform:
  module_source: ""
  state_backend: local
  state_config: {}
  required_tags: {}

patterns:
  - name: health-check-endpoint
    enabled: true
    config:
      path: /healthz
      check_database: true

  - name: structured-logging
    enabled: true
    config:
      format: json
      include_correlation_id: true
```

> **Reminder:** The app creator sees: "Preparing your app for the Retail On-Prem Platform..." — never "Harbor", "Vault", "Flux", or "longhorn".

---

## DevOps Quick Start Guide

> **Audience: DevOps / Platform Engineering.**
> This section helps you create your first deployment profile.

### Step 1: Copy a starter profile

Pick the example closest to your platform (Azure, AWS, or On-Prem above) and save it as:
```
~/.claude/devops-profiles/your-org-name.yml
```

### Step 2: Fill in your platform details

At minimum, fill in:
- `profile_name` and `display_name` (the display name is what app creators see — make it friendly)
- `cloud` (azure, aws, gcp, on-prem)
- `registry.url` (where container images are stored)
- `secrets.store` (where secrets live)
- `database` section (how apps connect to databases)
- `patterns` (which code transformations your platform requires)

### Step 3: Distribute to app creators

Option A — Install script (recommended):
```bash
# Create a repo with your profiles and an install script
# App creators run one command:
curl -sL https://your-org.github.io/devops-profiles/install.sh | bash
```

Option B — Manual copy:
```bash
# Copy the profile to the app creator's machine
cp your-org-name.yml ~/.claude/devops-profiles/
```

Option C — Project-level (per-app override):
```bash
# Drop a profile in the project root for a specific app
cp your-org-name.yml /path/to/project/.devops-profile.yml
```

### Step 4: Test it

Build a test app with /make-it, then run `/ship-it your-org-name`. Verify:
- All patterns applied correctly
- App still starts after transformation
- PR contains the right infrastructure changes
- **No technical jargon leaked into the app creator's output** (this is critical)

### What app creators experience after setup

The app creator types `/ship-it`. That's it. They see:
```
"I found a deployment setup from your DevOps team (Your Org Platform).
 I need to make N updates to prepare your app...
 Done! Review request sent."
```

They never know the profile exists. They never edit YAML. They never learn about your platform's internals. They just build their app and type `/ship-it`.

---

## Keeping Profiles Universal

Profiles are the **only** place where org-specific or cloud-specific logic lives. The rest of the system stays universal:

| Component | Contains org/cloud specifics? | Why |
|---|---|---|
| /make-it scaffold | NO | Builds Docker Compose apps that work anywhere |
| build-standards.md | NO | Universal quality checks, not cloud-specific |
| /ship-it skill | NO | Reads profile, delegates work, creates PR |
| /resume-it skill | NO | Applies patterns from profile, doesn't know which cloud |
| /argo-it skill | NO | Reads conventions from profile, generates matching manifests |
| **Deployment profile** | **YES** | The ONE place where "our org uses Azure Key Vault" lives |

This means:
- /make-it works for any organization without modification
- A new org just writes a new profile — no skill changes needed
- Multiple orgs can use /make-it simultaneously with different profiles
- The open-source skills never contain proprietary platform details
