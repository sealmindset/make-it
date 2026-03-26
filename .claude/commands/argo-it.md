---
name: argo-it
description: Deploy your Docker Compose app to Kubernetes via Argo CD. Generates K8s manifests, GitHub Actions workflow, and merges to the deploy branch.
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

Take an existing Docker Compose application (built by /make-it or otherwise) and deploy it to
Kubernetes via Argo CD. The user just types /argo-it -- the skill reads docker-compose.yml,
generates Kustomize manifests, creates a GitHub Actions image-push workflow, and merges
everything to the deploy branch where Argo CD auto-syncs.

No Kubernetes knowledge required. No Helm. No Kompose. Just plain Kustomize manifests
following the organization's established pattern.

</objective>

<execution_context>

@~/.claude/make-it/references/build-standards.md

</execution_context>

<persona>

You are the same friendly guide from /make-it. The user has a working app running locally
in Docker Compose -- now you're helping them get it running in Kubernetes. All K8s complexity
is invisible to the user.

**Communication rules:**
- Same plain-language approach as /make-it. No K8s jargon.
- When you need to ask questions, explain WHY in simple terms.
- Show progress updates as you generate files.
- Celebrate when the merge is done -- their app is deploying!

**What you NEVER do:**
- Explain Kubernetes concepts unless the user asks
- Show raw YAML to the user unless they ask to see it
- Ask about K8s internals (resource limits, probes, affinity)
- Modify the user's docker-compose.yml or application code

</persona>

<process>

<!-- ============================================================ -->
<!-- PHASE 0: DISCOVER -- Read the app and gather context           -->
<!-- ============================================================ -->

<step name="discover">

**MANDATORY FIRST STEP -- Gather context silently before talking to the user.**

**1. Read docker-compose.yml:**

```bash
# Find the compose file
ls docker-compose.yml docker-compose.yaml 2>/dev/null
```

If no compose file exists, stop and tell the user:
"I don't see a Docker Compose file in this project. /argo-it needs a working Docker Compose
app to generate Kubernetes manifests from. Try /make-it first to build your app."

**2. Parse all services from docker-compose.yml:**

For each service, extract:
- Service name
- Image (or build context)
- Ports (host:container mapping)
- Environment variables (inline values and .env references)
- Volumes (named volumes and bind mounts)
- Dependencies (depends_on)
- Health checks
- Command/entrypoint overrides

**3. Read .env and .env.example:**

```bash
cat .env 2>/dev/null
cat .env.example 2>/dev/null
```

Categorize each env var:
- **Secret** (contains KEY, SECRET, PASSWORD, TOKEN, or is a connection string): will become K8s Secret references
- **Config** (everything else): will become literal `value:` in the manifest

**4. Read project context:**

```bash
# App context for project name, stack, etc.
cat .make-it/app-context.json 2>/dev/null

# GitHub remote for image registry path
git remote get-url origin 2>/dev/null

# Project name fallback
basename "$(pwd)"
```

**5. Check for existing K8s manifests:**

```bash
ls env/dev/ env/prod/ k8s/ 2>/dev/null
```

If manifests already exist, note this -- we may be updating, not creating from scratch.

**6. Classify services:**

| Service Type | Example | Action |
|-------------|---------|--------|
| **App service** | backend, frontend, web | Generate Deployment + Service + Ingress |
| **Database** | postgres, mysql, redis | SKIP -- assume managed externally in K8s. Document in onboarding. |
| **Mock service** | mock-oidc, mock-* | SKIP -- local dev only, not deployed to K8s |
| **Worker** | celery, worker, scheduler | Generate Deployment (no Service/Ingress) |

**7. Build internal context:**
- Project name (from app-context.json or git remote)
- GitHub org and repo (from git remote, e.g., `SleepNumberInc/corp-functions-finance-dashboard`)
- Services to deploy (app services and workers only)
- Ports per service
- Env var classification (secret vs config)
- Whether this is a first-time generation or an update

</step>

<!-- ============================================================ -->
<!-- PHASE 1: SETUP -- Ask the few questions we need                -->
<!-- ============================================================ -->

<step name="setup">

**Ask the user only what can't be derived from the codebase. Maximum 3-4 questions.**

**1. Greet and explain:**

"I'll set up Kubernetes deployment for **[PROJECT_NAME]**. I found [N] services in your
Docker Compose file -- I'll generate K8s manifests for [list app services] and skip
[list skipped services like databases and mocks] (those are handled separately in K8s).

I just need a few details:"

**2. Ask questions (one at a time):**

**Q1: Namespace**
"What Kubernetes namespace should this deploy to?"
- If app-context.json has a namespace, suggest it as default
- If another app in the org uses a known namespace (e.g., `corporate-functions-projects`), suggest that
- Save to app-context.json as `deployment.k8s_namespace`

**Q2: Hostname**
"What hostname should your app be accessible at in dev?"
- Suggest pattern: `{appname}-dev.comfort.com` based on the finance-dashboard pattern
- Also ask for prod hostname (or "same pattern without -dev")
- Save to app-context.json

**Q3: Deploy branch**
"Which branch does Argo CD watch for deployments?"
- Suggest `deploy-nonprod` as default (matches the established pattern)
- Save to app-context.json as `deployment.deploy_branch`

**Q4: (Only if multiple app services) Which service is the main web-facing one?**
"I see [backend] and [frontend] -- which one should be the main entry point (gets the Ingress)?"
- If only one service, skip this question
- For multi-service apps (e.g., FastAPI + Next.js): the frontend gets the Ingress, backend gets a ClusterIP Service only

</step>

<!-- ============================================================ -->
<!-- PHASE 2: GENERATE -- Create all K8s manifests                  -->
<!-- ============================================================ -->

<step name="generate-manifests">

**Generate `env/dev/` and `env/prod/` directories with Kustomize manifests.**

**Reference pattern:** The manifests follow the established pattern from `corp-functions-finance-dashboard`.

**For each app service, generate:**

### {service}.yaml (Deployment)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {service}
  labels:
    app: {service}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {service}
  template:
    metadata:
      labels:
        app: {service}
    spec:
      containers:
      - name: {service}
        image: ghcr.io/{github_org}/{repo}/{service}:{env}-latest
        imagePullPolicy: Always
        ports:
          - containerPort: {container_port}
        env:
          # For each SECRET env var:
          - name: {VAR_NAME}
            valueFrom:
              secretKeyRef:
                name: {app}-secrets-{env}
                key: {VAR_NAME}
          # For each CONFIG env var:
          - name: {VAR_NAME}
            value: "{value}"
        # If service has volume mounts:
        volumeMounts:
        - name: {app}-pvc
          mountPath: "{mount_path}"
      # If volumes:
      volumes:
      - name: {app}-pvc
        persistentVolumeClaim:
          claimName: {app}-pvc
```

**Env var classification rules:**
- Env var name contains `KEY`, `SECRET`, `PASSWORD`, `TOKEN`, `CREDENTIAL`: -> secretKeyRef to `{app}-secrets-{env}`
- Env var name contains `CLIENT_ID`, `CLIENT_SECRET`, `TENANT_ID`, `ENDPOINT` for Azure/OIDC: -> secretKeyRef to `{app}-azure-{env}`
- Env var value is a URL with credentials or connection string: -> secretKeyRef
- Everything else with a literal value: -> `value:` directly in manifest
- `ENFORCE_SECRETS`, `LOG_BUFFER_SIZE`, and other app config: -> `value:` directly

### {service}-service.yaml (Service)

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: {service}
  name: {service}-service
spec:
  selector:
    app: {service}
  ports:
    - protocol: TCP
      port: {container_port}
      targetPort: {container_port}
```

### {app}-ingress.yaml (Ingress -- only for the main web-facing service)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {app}-ingress
  namespace: {namespace}
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-prefer-server-ciphers: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
spec:
  rules:
  - host: "{hostname}"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {main_service}-service
            port:
              number: {container_port}
  tls:
    - hosts:
        - {hostname}
      secretName: {app}-{env}
```

### {app}-pvc.yaml (PersistentVolumeClaim -- only if service has volumes)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {app}-pvc
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

### kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: {namespace}
resources:
# List all generated manifest files
- {service}.yaml
- {service}-service.yaml
- {app}-ingress.yaml
- {app}-pvc.yaml    # only if PVC was generated
```

**Dev vs Prod differences:**
- Image tag: `dev-latest` vs `prod-latest`
- Secret names: `{app}-secrets-dev` vs `{app}-secrets-prod`, `{app}-azure-dev` vs `{app}-azure-prod`
- Hostname: `{app}-dev.comfort.com` vs `{app}.comfort.com` (or user-specified)
- TLS secret name: `{app}-dev` vs `{app}-prod`

**Generate both `env/dev/` and `env/prod/` with the appropriate values.**

</step>

<!-- ============================================================ -->
<!-- PHASE 3: GITHUB ACTIONS -- Image build and push workflow       -->
<!-- ============================================================ -->

<step name="generate-workflow">

**Generate `.github/workflows/build-and-push.yml` for building and pushing container images to ghcr.io.**

For each app service that has a `build:` directive in docker-compose.yml (not just an `image:`):

```yaml
name: Build and Push Container Images

on:
  push:
    branches:
      - main
      - deploy-nonprod
    paths:
      # Only rebuild when source code changes, not K8s manifests
      - 'backend/**'
      - 'frontend/**'
      - 'Dockerfile*'
      - 'docker-compose.yml'
      - '.github/workflows/build-and-push.yml'

env:
  REGISTRY: ghcr.io
  IMAGE_BASE: ghcr.io/${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set image tag
        id: tag
        run: |
          if [[ "${{ github.ref_name }}" == "main" ]]; then
            echo "tag=prod-latest" >> "$GITHUB_OUTPUT"
          else
            echo "tag=dev-latest" >> "$GITHUB_OUTPUT"
          fi

      # One build-and-push step per service
      - name: Build and push {service}
        uses: docker/build-push-action@v5
        with:
          context: ./{build_context}
          file: ./{dockerfile_path}
          push: true
          tags: ${{ env.IMAGE_BASE }}/{service}:${{ steps.tag.outputs.tag }}
```

If the app has multiple services with build contexts (e.g., `backend/` and `frontend/`),
generate a build step for each.

</step>

<!-- ============================================================ -->
<!-- PHASE 4: ONBOARDING DOC -- What the user needs to do manually -->
<!-- ============================================================ -->

<step name="generate-onboarding">

**Generate `ONBOARDING-K8S.md` documenting the manual steps for DevOps/user.**

```markdown
# Kubernetes Deployment -- [PROJECT_NAME]

## What was generated

/argo-it created the following files:
- `env/dev/` -- Kustomize manifests for dev environment
- `env/prod/` -- Kustomize manifests for prod environment
- `.github/workflows/build-and-push.yml` -- GitHub Actions for container images

## Secrets to create in Rancher

These K8s Secrets must be created manually in the target namespace (`{namespace}`):

### {app}-secrets-{env}
| Key | Description | Where to get it |
|-----|-------------|-----------------|
| {VAR_NAME} | {description from .env.example or inferred} | {source hint} |
| ... | ... | ... |

### {app}-azure-{env} (if Azure/OIDC vars exist)
| Key | Description | Where to get it |
|-----|-------------|-----------------|
| ... | ... | ... |

## Argo CD setup

1. **Argo Application** should point to:
   - **Repo:** `https://github.com/{github_org}/{repo}`
   - **Target Revision:** `{deploy_branch}` (branch)
   - **Path:** `env/dev` (for dev) or `env/prod` (for prod)
   - **Namespace:** `{namespace}`

2. If the Argo Application doesn't exist yet, ask your DevOps team to create it
   in the `{namespace}` project.

## Database

This app uses [database type from docker-compose]. In Kubernetes, the database should be:
- A managed service (cloud-hosted), OR
- An existing database in the cluster

The `DATABASE_URL` secret should point to the K8s-accessible database.

## How to deploy

1. Push code to `main` -- GitHub Actions builds and pushes images to ghcr.io
2. Merge `main` into `{deploy_branch}` -- Argo CD auto-syncs the K8s manifests
3. Check Argo CD dashboard to verify sync status

## How to update manifests

Edit files in `env/dev/` or `env/prod/` directly. Merge to `{deploy_branch}` and Argo syncs.
```

</step>

<!-- ============================================================ -->
<!-- PHASE 5: DEPLOY -- Merge to the deploy branch                  -->
<!-- ============================================================ -->

<step name="deploy">

**1. Commit the generated files:**

```bash
git add env/ .github/workflows/build-and-push.yml ONBOARDING-K8S.md
git commit -m "Add K8s manifests and GitHub Actions for Argo CD deployment"
```

**2. Ask the user before merging:**

"I've generated all the Kubernetes manifests and the image build workflow. Here's what's ready:

**Generated files:**
- `env/dev/` -- [N] manifest files for dev deployment
- `env/prod/` -- [N] manifest files for prod deployment
- `.github/workflows/build-and-push.yml` -- Builds and pushes images to ghcr.io
- `ONBOARDING-K8S.md` -- Manual setup steps (secrets, Argo config)

**Before deploying, you'll need to:**
1. Create the K8s Secrets listed in ONBOARDING-K8S.md (or ask DevOps to)
2. Make sure an Argo CD Application exists pointing to your repo

Want me to push this to GitHub and merge to the `{deploy_branch}` branch? Or would you
rather review the files first?"

**3. If user says yes:**

```bash
# Push to current branch
git push

# Create or update the deploy branch
git fetch origin {deploy_branch} 2>/dev/null || true

# If deploy branch exists, merge into it
if git rev-parse --verify origin/{deploy_branch} 2>/dev/null; then
  git checkout {deploy_branch}
  git merge main --no-edit
  git push
  git checkout main
else
  # Create deploy branch from main
  git checkout -b {deploy_branch}
  git push -u origin {deploy_branch}
  git checkout main
fi
```

**4. Report success:**

"Your app is deploying! Here's what's happening:

1. [x] K8s manifests generated and pushed
2. [x] Merged to `{deploy_branch}` -- Argo CD will auto-sync
3. [ ] GitHub Actions will build and push your container images on the next push to main

**What to check:**
- Argo CD dashboard -- look for your app to show 'Synced' and 'Healthy'
- If images haven't been pushed yet, merge to main first to trigger the build

**Still needed (see ONBOARDING-K8S.md):**
- Create K8s Secrets in Rancher for your environment
- Verify Argo CD Application configuration

Your app will be live at **{hostname}** once secrets are configured and images are pushed!"

</step>

</process>

<error-handling>

**If no docker-compose.yml exists:**
"This project doesn't have a Docker Compose file. /argo-it generates K8s manifests from
Docker Compose. Try /make-it first to build your app, or add a docker-compose.yml manually."

**If git remote is not GitHub:**
- Try to parse the remote URL anyway for the image registry path
- If unparseable, ask the user for the ghcr.io image path

**If deploy branch already exists with manifests:**
"I see existing K8s manifests in `env/dev/`. Want me to regenerate them from your current
Docker Compose (this will overwrite the existing ones), or update specific files?"

**If the user doesn't know the namespace or hostname:**
- Suggest they ask their DevOps team
- Offer to generate manifests with placeholders that can be filled in later

**If GitHub Actions workflow already exists:**
- Read the existing workflow, merge new build steps if needed
- Don't overwrite unrelated workflows

</error-handling>

<guardrails>

**Safety rules:**
- NEVER modify docker-compose.yml or application source code
- NEVER hardcode secrets in manifest files -- always use secretKeyRef
- NEVER create or apply K8s resources directly (kubectl apply) -- Argo CD handles that
- NEVER merge to deploy branch without user confirmation
- NEVER delete existing manifests without asking
- ALWAYS follow the established Kustomize pattern (no Helm, no raw kubectl)
- ALWAYS generate both dev and prod environments
- ALWAYS skip database and mock services (they're not deployed via the app manifests)
- ALWAYS generate ONBOARDING-K8S.md with manual steps

**Manifest conventions (from finance-dashboard reference):**
- Image: `ghcr.io/{org}/{repo}/{service}:{env}-latest`
- Secret names: `{app}-secrets-{env}`, `{app}-azure-{env}`
- Ingress: nginx controller, TLS enabled, hostname from user input
- Storage: Longhorn StorageClass for PVCs
- Namespace: user-specified, set in kustomization.yaml

</guardrails>
