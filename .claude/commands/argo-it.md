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
generates Kustomize manifests, creates a CI workflow for image publishing, and merges
everything to the deploy branch where Argo CD auto-syncs.

No Kubernetes knowledge required. The skill detects org conventions from existing manifests
and adapts to any K8s environment.

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
<!-- PHASE 0: DISCOVER -- Read the app and detect conventions       -->
<!-- ============================================================ -->

<step name="discover">

**MANDATORY FIRST STEP -- Gather context silently before talking to the user.**

**1. Read docker-compose.yml:**

```bash
ls docker-compose.yml docker-compose.yaml 2>/dev/null
```

If no compose file exists, stop and tell the user:
"I don't see a Docker Compose file in this project. /argo-it needs a working Docker Compose
app to generate Kubernetes manifests from. Try /make-it first to build your app."

**2. Parse all services from docker-compose.yml:**

For each service, extract:
- Service name
- Image (or build context and Dockerfile path)
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
- **Secret** (name contains KEY, SECRET, PASSWORD, TOKEN, CREDENTIAL, or value is a connection string/URL with credentials): will become K8s Secret references
- **Config** (everything else with a literal value): will become literal `value:` in the manifest

**4. Read project context:**

```bash
# App context for project name, stack, etc.
cat .make-it/app-context.json 2>/dev/null

# Git remote for registry path
git remote get-url origin 2>/dev/null

# Project name fallback
basename "$(pwd)"
```

**5. DETECT EXISTING CONVENTIONS -- This is the key step.**

Check if K8s manifests already exist in this project or in sibling repos:

```bash
# Check this repo for existing manifests
ls env/dev/ env/prod/ k8s/ deploy/ manifests/ 2>/dev/null
find . -name "kustomization.yaml" -not -path "./.git/*" 2>/dev/null
find . -name "Chart.yaml" -not -path "./.git/*" 2>/dev/null

# Check for existing CI workflows
ls .github/workflows/ 2>/dev/null
```

**If existing manifests are found, READ THEM and extract the org's conventions:**

```bash
# Read kustomization.yaml to learn the pattern
cat env/dev/kustomization.yaml k8s/kustomization.yaml 2>/dev/null

# Read any Deployment to learn image registry, naming, secret patterns
cat env/dev/*.yaml k8s/*.yaml 2>/dev/null | head -200

# Read Ingress or IngressRoute to learn controller type and hostname pattern
grep -l "Ingress\|IngressRoute" env/dev/*.yaml k8s/*.yaml 2>/dev/null | head -1 | xargs cat 2>/dev/null

# Read PVC to learn storage class
grep "storageClassName" env/dev/*.yaml k8s/*.yaml 2>/dev/null
```

**Extract these conventions from existing manifests (if found):**

| Convention | How to detect | Fallback if not found |
|-----------|---------------|----------------------|
| **Container registry** | Image field in Deployment (e.g., `ghcr.io/org/repo/service:tag`) | Ask user |
| **Image tag strategy** | Tag in image field (e.g., `dev-latest`, `v1.2.3`, git SHA) | `{env}-latest` |
| **Ingress controller** | Annotations on Ingress (`nginx.ingress.kubernetes.io`, `traefik.ingress.kubernetes.io`, `alb.ingress.kubernetes.io`) or Traefik IngressRoute CRD (`kind: IngressRoute`) | Ask user |
| **Hostname pattern** | `host:` field in Ingress rules or IngressRoute `match:` | Ask user |
| **TLS config** | `tls:` section in Ingress or IngressRoute | Match existing pattern |
| **Storage class** | `storageClassName` in PVC | Ask user |
| **Secret naming** | `secretKeyRef.name` in Deployment env vars | `{app}-secrets-{env}` |
| **Namespace** | `namespace:` in kustomization.yaml or Ingress metadata | Ask user |
| **Manifest structure** | Directory layout (env/dev, k8s/, etc.) | `env/{env}/` |
| **Deploy branch** | Check for deploy-* branches: `git branch -r \| grep deploy` | Ask user |

**Also check sibling repos for org conventions** (if the user's git remote reveals an org):

```bash
# Check for deploy branches in this repo
git branch -r 2>/dev/null | grep -i deploy
```

**6. Classify services:**

| Service Type | How to identify | Action |
|-------------|----------------|--------|
| **App service** | Has `build:` or app image, exposes ports | Generate Deployment + Service |
| **Web-facing service** | App service that serves HTTP on well-known ports (80, 443, 3000, 5000, 8000, 8080) | Also gets Ingress |
| **Database** | Image is postgres, mysql, mariadb, mongo, redis, etc. | SKIP -- document in onboarding |
| **Mock service** | Name starts with mock-*, or is in docker-compose `profiles: [dev]` | SKIP -- local dev only |
| **Worker** | Has no ports, or is named worker/celery/scheduler | Generate Deployment only (no Service/Ingress) |

**7. Build internal context:**
- Project name
- Git org and repo (from remote URL)
- Services to deploy (app + worker only)
- Ports per service
- Env var classification (secret vs config)
- **Detected conventions** (registry, ingress controller, storage class, etc.)
- **What needs to be asked** (anything not detected)
- Whether this is first-time generation or an update

</step>

<!-- ============================================================ -->
<!-- PHASE 1: SETUP -- Ask only what couldn't be detected           -->
<!-- ============================================================ -->

<step name="setup">

**Only ask questions for conventions that could NOT be detected from existing manifests.**
If everything was detected, skip directly to generation with a confirmation.

**1. Greet and explain:**

"I'll set up Kubernetes deployment for **[PROJECT_NAME]**. I found [N] services in your
Docker Compose file -- I'll generate K8s manifests for [list app services] and skip
[list skipped services] (those are handled separately in K8s).

[If conventions detected:] I found existing K8s manifests and will follow the same patterns:
- Registry: [detected registry]
- Ingress: [detected controller]
- Namespace: [detected namespace]

[If some questions needed:] I just need a few details:"

**2. Ask ONLY what's missing (skip if detected):**

**Container registry** (if not detected from existing manifests):
"Where should container images be published?"
- Options: GitHub Container Registry (ghcr.io), Docker Hub, AWS ECR, Azure ACR, custom
- For ghcr.io: derive path from git remote (e.g., `ghcr.io/{org}/{repo}/{service}`)

**Namespace** (if not detected):
"What Kubernetes namespace should this deploy to?"
- Save to app-context.json as `deployment.k8s_namespace`

**Hostname** (if not detected from existing Ingress):
"What hostname should your app be accessible at?"
- For dev and prod separately
- Save to app-context.json

**Ingress controller** (if not detected):
"What ingress controller does your cluster use?"
- Options: Traefik IngressRoute (CRD), Traefik standard Ingress, nginx, AWS ALB, Istio, none (ClusterIP only)
- If Traefik: "Does your cluster use Traefik IngressRoute CRDs or standard Kubernetes Ingress with Traefik annotations?"
- IngressRoute CRDs are preferred when available (more control over entrypoints like `websecure`)

**Storage class** (only if the app uses volumes AND not detected):
"What storage class does your cluster use for persistent volumes?"
- Common options: longhorn, gp3, standard, local-path

**Deploy branch** (if not detected):
"Which branch does Argo CD watch for deployments?"
- Suggest `deploy-nonprod` if no existing pattern found
- Save to app-context.json as `deployment.deploy_branch`

**Main service** (only if multiple web-facing services):
"I see [backend] and [frontend] -- which one should be the main entry point?"
- The selected service gets the Ingress; others get ClusterIP Service only

</step>

<!-- ============================================================ -->
<!-- PHASE 2: GENERATE -- Create K8s manifests                      -->
<!-- ============================================================ -->

<step name="generate-manifests">

**Generate manifests using detected conventions (or user answers for anything not detected).**

Determine the manifest directory structure:
- If existing manifests use `env/dev/` and `env/prod/`: follow that
- If existing manifests use `k8s/`: follow that
- Default: `env/dev/` and `env/prod/`

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
        image: {registry}/{image_path}:{tag}
        imagePullPolicy: Always
        ports:
          - containerPort: {container_port}
        env:
          # SECRET env vars -> secretKeyRef
          - name: {VAR_NAME}
            valueFrom:
              secretKeyRef:
                name: {detected_secret_name_pattern}
                key: {VAR_NAME}
          # CONFIG env vars -> literal value
          - name: {VAR_NAME}
            value: "{value}"
        # If volumes exist:
        volumeMounts:
        - name: {app}-pvc
          mountPath: "{mount_path}"
      # If the service runs database migrations (e.g., Alembic, Django, Prisma):
      initContainers:
      - name: {service}-migrate
        image: {registry}/{image_path}:{tag}
        command: ["python", "-m", "alembic", "upgrade", "head"]  # adapt for framework
        env:
          # Same env vars as main container (secrets + config)
          - name: DATABASE_URL
            valueFrom:
              secretKeyRef:
                name: {detected_secret_name_pattern}
                key: DATABASE_URL
      # If volumes:
      volumes:
      - name: {app}-pvc
        persistentVolumeClaim:
          claimName: {app}-pvc
```

**Init container rules:**
- Use init containers for DB migrations (preferred over K8s Jobs -- no cluster-level RBAC needed)
- Same image as the main container, different command
- Same secret/config env vars as main container (needs DB access)
- Adapt command for framework: Alembic (`alembic upgrade head`), Django (`manage.py migrate`), Prisma (`prisma migrate deploy`), Knex (`knex migrate:latest`)
- Only add if the app has a database migration tool (check for `alembic/`, `migrations/`, `prisma/`, etc.)

**Registry and image path rules:**
- Use detected registry pattern from existing manifests if available
- For ghcr.io: `ghcr.io/{github_org}/{repo}/{service}:{env}-latest`
- For ECR: `{account}.dkr.ecr.{region}.amazonaws.com/{repo}/{service}:{tag}`
- For ACR: `{registry}.azurecr.io/{repo}/{service}:{tag}`
- For Docker Hub: `{org}/{service}:{tag}`

**Secret grouping rules:**
- Follow detected secret naming pattern from existing manifests
- If no pattern detected, group by purpose:
  - `{app}-secrets-{env}` for general app secrets (DB, JWT, API keys)
  - `{app}-{provider}-{env}` for provider-specific secrets (azure, aws, oidc)

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

### {app}-ingress.yaml (Ingress -- only for web-facing service)

Generate based on detected ingress controller:

**Traefik IngressRoute (CRD -- preferred when Traefik is available):**
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {app}-ingress
  namespace: {namespace}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`{hostname}`)
      kind: Rule
      services:
        - name: {main_service}-service
          port: {container_port}
      # Optional middlewares (user's choice -- add if needed):
      # middlewares:
      #   - name: {app}-ratelimit
  tls:
    secretName: {tls_secret_name}
```

If the user needs middlewares, generate them as separate Traefik Middleware CRDs:
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: {app}-ratelimit
  namespace: {namespace}
spec:
  rateLimit:
    average: 100
    burst: 50
```

**Traefik standard Ingress (annotations-based):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {app}-ingress
  namespace: {namespace}
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
```

**nginx:**
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
```

**AWS ALB:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {app}-ingress
  namespace: {namespace}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: {cert_arn}
```

**If existing Ingress/IngressRoute manifests were found, copy their structure exactly.**

The spec section for standard Ingress controllers (nginx, ALB, Traefik annotations):
```yaml
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
      secretName: {tls_secret_name}
```

### {app}-pvc.yaml (PersistentVolumeClaim -- only if volumes exist)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {app}-pvc
spec:
  storageClassName: {detected_or_asked_storage_class}
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
- {service}.yaml
- {service}-service.yaml
- {app}-ingress.yaml      # Ingress or IngressRoute
- {app}-pvc.yaml           # only if PVC was generated
# If External Secrets Operator:
# - {app}-external-secret.yaml
```

**If the user is using External Secrets Operator**, also generate:

### {app}-external-secret.yaml (optional -- only if ESO is available)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {app}-secrets-{env}
  namespace: {namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: {team-name}-secret-store
    kind: SecretStore
  target:
    name: {app}-secrets-{env}
  data:
    - secretKey: {VAR_NAME}
      remoteRef:
        key: {secret_server_path}
        property: {VAR_NAME}
```

Only generate ExternalSecret if the user confirms ESO is available for their namespace.
Otherwise, document manual secret creation in ONBOARDING-K8S.md.

**Environment differences (dev vs prod):**
- Image tag: `dev-latest` vs `prod-latest` (or detected pattern)
- Secret names: `{app}-secrets-dev` vs `{app}-secrets-prod` (or detected pattern)
- Hostname: dev hostname vs prod hostname (from user input or detected pattern)
- TLS secret name: follows detected pattern or `{app}-tls-{env}`

**Generate manifests for all configured environments.**

</step>

<!-- ============================================================ -->
<!-- PHASE 3: CI WORKFLOW -- Image build and push                   -->
<!-- ============================================================ -->

<step name="generate-workflow">

**Generate a CI workflow for building and pushing container images.**

Detect the CI system from the repo:
- `.github/workflows/` exists -> GitHub Actions
- `.gitlab-ci.yml` exists -> GitLab CI
- `Jenkinsfile` exists -> Jenkins
- `azure-pipelines.yml` exists -> Azure DevOps
- None found -> default to GitHub Actions

**For GitHub Actions** (most common):

Generate `.github/workflows/build-and-push.yml`:

```yaml
name: Build and Push Container Images

on:
  push:
    branches:
      - main
      - {deploy_branch}
    paths:
      # Only rebuild when source code changes, not K8s manifests
      - '{build_context}/**'
      - 'Dockerfile*'
      - 'docker-compose.yml'
      - '.github/workflows/build-and-push.yml'

env:
  REGISTRY: {registry_host}
  IMAGE_BASE: {registry_host}/{image_base_path}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to container registry
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

      # One build step per service with a build context
      - name: Build and push {service}
        uses: docker/build-push-action@v5
        with:
          context: ./{build_context}
          file: ./{dockerfile_path}
          push: true
          tags: ${{ env.IMAGE_BASE }}/{service}:${{ steps.tag.outputs.tag }}
```

**Adapt the login step for non-ghcr.io registries:**
- ECR: use `aws-actions/amazon-ecr-login@v2`
- ACR: use `azure/docker-login@v1`
- Docker Hub: use `docker/login-action@v3` with Docker Hub credentials

**If existing CI workflows are found**, read them and either:
- Add the image build steps to an existing workflow, or
- Create a new workflow that doesn't conflict

</step>

<!-- ============================================================ -->
<!-- PHASE 4: ONBOARDING DOC                                        -->
<!-- ============================================================ -->

<step name="generate-onboarding">

**Generate `ONBOARDING-K8S.md` documenting manual steps.**

```markdown
# Kubernetes Deployment -- [PROJECT_NAME]

## What was generated

/argo-it created the following files:
- `{manifest_dir}/dev/` -- Kustomize manifests for dev environment
- `{manifest_dir}/prod/` -- Kustomize manifests for prod environment
- `.github/workflows/build-and-push.yml` -- CI workflow for container images
- This file

## TLS Certificate

Your app needs a TLS certificate for `{hostname}`.

1. **Generate a CSR** (Certificate Signing Request) for `{hostname}`
2. **Submit a request** through your org's cert provisioning process (e.g., ServiceNow ticket)
3. **Create a K8s TLS secret** once the cert is issued:
   ```bash
   kubectl create secret tls {tls_secret_name} \
     --cert=path/to/cert.pem \
     --key=path/to/key.pem \
     -n {namespace}
   ```

Note: Certs are per-app and typically valid for 1 year. Set a reminder to renew.

## Secrets to create

These K8s Secrets must be created in the target namespace (`{namespace}`).

**Option A: Manual creation (quick start)**
Create secrets via your cluster management UI (e.g., Rancher) or kubectl:
```bash
kubectl create secret generic {app}-secrets-{env} \
  --from-literal=DATABASE_URL='...' \
  --from-literal=SECRET_KEY='...' \
  -n {namespace}
```

**Option B: External Secrets Operator (recommended for production)**
If your namespace has been onboarded to External Secrets Operator, create an ExternalSecret
that pulls from your team's SecretStore:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {app}-secrets-{env}
  namespace: {namespace}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: {team-name}-secret-store
    kind: SecretStore
  target:
    name: {app}-secrets-{env}
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: {secret_server_path}
        property: DATABASE_URL
```
Ask your DevOps team if your namespace is onboarded to ESO.

### {app}-secrets-{env}
| Key | Description | Where to get it |
|-----|-------------|-----------------|
| {VAR_NAME} | {description} | {source hint} |

### {app}-{provider}-{env} (if provider-specific secrets exist)
| Key | Description | Where to get it |
|-----|-------------|-----------------|
| {VAR_NAME} | {description} | {source hint} |

## Namespace

Your app deploys to namespace `{namespace}`. Namespaces are typically created by
your infrastructure/compute team -- if this namespace doesn't exist yet, request it
before deploying.

## Argo CD setup

1. **Argo Application** should point to:
   - **Repo:** `{repo_url}`
   - **Target Revision:** `{deploy_branch}` (branch)
   - **Path:** `{manifest_dir}/dev` (for dev) or `{manifest_dir}/prod` (for prod)
   - **Namespace:** `{namespace}`

2. If the Argo Application doesn't exist yet, ask your DevOps team to create it
   within your team's Argo project.

## Database

[If database service was skipped from docker-compose:]
This app uses {database_type} locally via Docker Compose. In Kubernetes, you need:
- A managed database service (cloud-hosted), OR
- An existing database in the cluster

Set the `DATABASE_URL` secret to point to the K8s-accessible database.

## Local K8s testing (optional)

If you have a local K8s cluster (Rancher Desktop, minikube, kind, Docker Desktop K8s):

```bash
# Build images locally
docker compose build

# For Rancher Desktop (nerdctl):
nerdctl --namespace k8s.io load < $(docker save {image})

# Apply manifests to local cluster
kubectl apply -k {manifest_dir}/dev/

# Verify pods are running
kubectl get pods -n {namespace}

# Clean up
kubectl delete -k {manifest_dir}/dev/
```

This tests the exact same Kustomize manifests that Argo CD uses.

## How to deploy

1. Push code to `main` -- CI builds and pushes images to {registry}
2. Merge `main` into `{deploy_branch}` -- Argo CD auto-syncs the K8s manifests
3. Check Argo CD dashboard to verify sync status

## How to update manifests

Edit files in `{manifest_dir}/dev/` or `{manifest_dir}/prod/` directly.
Merge to `{deploy_branch}` and Argo syncs automatically.
```

</step>

<!-- ============================================================ -->
<!-- PHASE 5: DEPLOY -- Commit and merge to deploy branch           -->
<!-- ============================================================ -->

<step name="deploy">

**1. Commit the generated files:**

```bash
git add env/ .github/workflows/ ONBOARDING-K8S.md
git commit -m "Add K8s manifests and CI workflow for Argo CD deployment"
```

**2. Ask the user what they want to do:**

"I've generated all the Kubernetes manifests. Here's what's ready:

**Generated files:**
- `{manifest_dir}/dev/` -- [N] manifest files for dev
- `{manifest_dir}/prod/` -- [N] manifest files for prod
- `.github/workflows/build-and-push.yml` -- Image build pipeline
- `ONBOARDING-K8S.md` -- Setup steps for secrets and Argo

**What would you like to do?**

1. **Push and merge to `{deploy_branch}`** -- Argo CD will auto-sync (requires secrets to be created first)
2. **Test locally first** -- Apply to your local K8s cluster with `kubectl apply -k {manifest_dir}/dev/`
3. **Just push** -- Push to GitHub but don't merge to deploy branch yet (review first)
4. **Review files** -- Show me the generated manifests before doing anything"

**3. Execute based on user choice:**

**Option 1 (push + merge):**
```bash
git push

git fetch origin {deploy_branch} 2>/dev/null || true
if git rev-parse --verify origin/{deploy_branch} 2>/dev/null; then
  git checkout {deploy_branch}
  git merge main --no-edit
  git push
  git checkout main
else
  git checkout -b {deploy_branch}
  git push -u origin {deploy_branch}
  git checkout main
fi
```

**Option 2 (local test):**
```bash
# Build images locally
docker compose build

# Apply to local cluster
kubectl apply -k {manifest_dir}/dev/

# Check status
kubectl get pods -n {namespace}
kubectl get svc -n {namespace}
kubectl get ingress -n {namespace}
```

Then ask: "How does it look? Want me to push and merge to `{deploy_branch}` now?"

**Option 3 (just push):**
```bash
git push
```
"Pushed! When you're ready, merge to `{deploy_branch}` and Argo will pick it up."

**4. Report success (after deploy):**

"Your app is deploying!

1. [x] K8s manifests generated and pushed
2. [x] Merged to `{deploy_branch}` -- Argo CD will auto-sync
3. [ ] CI will build and push images on the next push to main

**Still needed (see ONBOARDING-K8S.md):**
- Create K8s Secrets in your cluster
- Verify Argo CD Application exists and is configured

Your app will be live at **{hostname}** once secrets are configured and images are pushed!"

</step>

</process>

<error-handling>

**If no docker-compose.yml exists:**
"This project doesn't have a Docker Compose file. /argo-it generates K8s manifests from
Docker Compose. Try /make-it first to build your app, or add a docker-compose.yml manually."

**If git remote is not recognizable:**
- Ask the user for the container registry and image path
- Don't assume any specific registry

**If existing manifests are found:**
"I see existing K8s manifests in `{dir}`. Want me to:
1. Regenerate them from your current Docker Compose (overwrites existing)
2. Update specific files only
3. Use them as a reference pattern for a new app"

**If the user doesn't know a setting (namespace, hostname, etc.):**
- Offer to generate manifests with `TODO` placeholders that can be filled in later
- "No worries -- I'll mark it as TODO in the manifest. You can fill it in later or ask your DevOps team."

**If kubectl is not available (for local testing):**
- Skip local test option
- "Local K8s testing requires kubectl and a local cluster (Rancher Desktop, minikube, etc.). You can still push to the deploy branch for Argo CD."

**If no CI system is detected:**
- Still generate the GitHub Actions workflow as default
- "I generated a GitHub Actions workflow. If your org uses a different CI system, you may need to adapt it."

</error-handling>

<guardrails>

**Safety rules:**
- NEVER modify docker-compose.yml or application source code
- NEVER hardcode secrets in manifest files -- always use secretKeyRef
- NEVER merge to deploy branch without user confirmation
- NEVER delete existing manifests without asking
- NEVER assume a specific registry, ingress controller, or storage class -- detect or ask
- ALWAYS detect conventions from existing manifests before asking questions
- ALWAYS generate both dev and prod environments
- ALWAYS skip database and mock services (they're not deployed via app manifests)
- ALWAYS generate ONBOARDING-K8S.md with manual steps
- ALWAYS offer local K8s testing as an option before deploying

**Convention detection priority:**
1. Existing manifests in THIS repo (highest priority -- follow exactly)
2. Patterns from app-context.json deployment settings
3. User answers to setup questions
4. Sensible defaults (lowest priority)

</guardrails>
