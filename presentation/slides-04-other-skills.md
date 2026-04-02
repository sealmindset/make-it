# SECTION 4: INDIVIDUAL SKILL DEEP DIVES

---

## Slide 18 -- /try-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. Large browser window mockup showing a clean web app:
dark sidebar, header bar, dashboard with cards and table. Green "LIVE" dot top-left.

Below the browser, 3-step flow:
Terminal icon (slate) "Type /try-it" → Play icon (blue) "App starts" → Pointer icon (green) "Explore"

Above browser: "Your app. Running. Right now."
```

**Slide Text:**
### /try-it -- See your app running in seconds

Type `/try-it` and your app appears in the browser.

**Behind the scenes:**
1. Checks if app is already running (skips startup if so)
2. Starts all containers (app, database, mock login server)
3. Runs smoke tests (login, pages, API health)
4. If anything breaks, fixes automatically
5. Generates a test report with screenshots

**What you get:**
- Your app at localhost with test users pre-configured
- TRY-IT-REPORT.md with screenshots of every page for every role
- Instructions: "Log in as Admin to see everything, or as User for the restricted view"

---

## Slide 19 -- /try-it: The Test Report

**Gemini Image Prompt:**
```
Plain white background, 16:9. Document mockup titled "TRY-IT-REPORT.md".

Sections:
1. "Test Results" -- grid of 8 green checkmarks: Health, Login, Dashboard, API,
   Permissions, Logs, Notifications, Settings
2. "Screenshots" -- 4 small thumbnail boxes: "Admin view", "Manager view",
   "User view", "Login page"
3. "Access" -- URL and test users listed
4. "Issues Found: 0" with green highlight

Clean, organized, confidence-building.
```

**Slide Text:**
### /try-it generates a confidence report

**TRY-IT-REPORT.md includes:**
- Test results for every feature (login, pages, API, permissions)
- Screenshots of every page for every user role
- Access instructions (URL, test credentials)
- Issues found (and whether they were auto-fixed)

**Share with your manager or stakeholders.** It's proof your app works.

---

## Slide 20 -- /resume-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A bookmark ribbon icon (purple #8B5CF6) at top center.

Below it, conversation mockup:
Assistant (purple border): "Welcome back! Here's where you left off:
- 3 features completed
- 2 to-do items remaining
- 1 security update applied (automatic)
- App is healthy

What would you like to work on?"

User (gray): "Add an export-to-Excel feature"

Below the conversation, a small status card showing: "Session state preserved in
.make-it-state.md -- your progress is never lost."
```

**Slide Text:**
### /resume-it -- Pick up exactly where you left off

Run `/resume-it` from your project directory. It reads your saved state and tells you:

- What was built and what's pending
- Any security fixes it applied automatically
- Whether new platform standards are available (it upgrades you)
- Suggested next steps from your to-do list

**What you can do:**
- "Add a new feature" -- describe it, /resume-it builds it
- "Fix a bug" -- describe it, /resume-it diagnoses and fixes
- "Work through my to-do list" -- it picks items and executes
- "Am I ready to deploy?" -- generates a readiness checklist

**Your app stays current with the latest security standards, even months later.**

---

## Slide 21 -- /resume-it: Standards Catch-Up

**Gemini Image Prompt:**
```
Plain white background, 16:9. A timeline diagram.

Left side: "Your app (built 6 months ago)" -- a box with features listed.
Right side: "Platform today" -- a larger box with the same features plus 3 new
ones highlighted in green: "Activity Logs", "Notifications", "App Settings"

An arrow connects them labeled "/resume-it catch-up"

Below the arrow: "New standards detected. Applied automatically. Zero effort from you."

The visual shows the gap between when you built and what's available now,
with /resume-it bridging it.
```

**Slide Text:**
### /resume-it keeps your app current -- automatically

**Scenario:** You built an app 6 months ago. Since then, /make-it added new standards: Activity Logs, Notifications, App Settings.

**What /resume-it does:**
1. Scans your app against the latest build-standards.md
2. Detects which new patterns are missing
3. Says: "I found 3 improvements available. Want me to apply them?"
4. You say yes
5. Activity Logs, Notifications, and Settings are added
6. Tests run to verify nothing broke
7. CHANGELOG.md updated

**You don't need to re-run /make-it. You don't need to know what changed. /resume-it bridges the gap.**

---

## Slide 22 -- /wrap-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A clean checklist mockup with a "Session Complete"
header and green checkmarks:

✓ Changes committed (3 commits)
✓ CHANGELOG.md updated
✓ TODO.md updated (2 completed, 1 added)
✓ Progress saved to .make-it-state.md
✓ Docker containers shut down (data preserved)
✓ No orphaned ports

Below the checklist, a "Next Session" box:
"When you run /resume-it:
1. Dashboard redesign (in progress)
2. Export feature (not started)
3. Accessibility audit (not started)"

Clean, organized, reassuring. Everything is saved.
```

**Slide Text:**
### /wrap-it -- Save your work and shut down cleanly

Type `/wrap-it` when you're done for the day.

**What it does:**
1. Commits any unsaved changes
2. Updates CHANGELOG.md with what you accomplished
3. Updates TODO.md (completed items removed, new items added)
4. Saves full session state for /resume-it to pick up
5. Shuts down Docker containers (data preserved for fast restart)
6. Reports what to expect next session

**What it never does:**
- Destroys your data (volumes preserved)
- Pushes code to remote (local only)
- Starts new work (you said you're done)

**Your next /resume-it session starts instantly, right where you left off.**

---

## Slide 23 -- /ship-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A horizontal pipeline flow:

Left: Terminal showing "/ship-it" (green #10B981)
Arrow right → Box 1: "Pre-check" (scan deps, lint, secrets)
Arrow right → Box 2: "Security" (NeMo tests, attestation)
Arrow right → Box 3: "Push & PR" (branch, commit, review)
Arrow right → Box 4: "CI Monitor" (watch, auto-fix)
Arrow right → Green flag: "Ready for review"

Below the pipeline, a note: "If CI fails, /ship-it fixes it and retries (up to 3x)"

A subtle dashed line from the flag leads to "DevOps takes it from here"
```

**Slide Text:**
### /ship-it -- One command to production

Type `/ship-it` and your code ships. That's your only job.

**What happens automatically:**
1. **Pre-push review** -- Lint, type-check, secret scan, dependency audit
2. **Security scan** -- Vulnerability check, auto-fix what's fixable
3. **AI safety** -- NeMo Guardrails test suite (if AI features exist)
4. **Branch & PR** -- Creates branch, commits, pushes, opens pull request
5. **CI monitoring** -- Watches the pipeline, auto-fixes failures (up to 3 cycles)
6. **Handoff** -- "Your app passed all checks. The team will review and deploy."

**Two modes:**
- `/ship-it` -- Full deployment pipeline
- `/ship-it save` -- Just save your work (draft PR, no review)

---

## Slide 24 -- /ship-it: The Deployment Journey

**Gemini Image Prompt:**
```
Plain white background, 16:9. A vertical flow with swim lanes:

Lane 1 "YOU": Three boxes: "Describe" → "Verify" → "Say ready"
Lane 2 "AUTOMATION": Dense series of boxes: "Scan" → "Fix" → "PR" → "CI" → "Remediate" → "Deploy to Dev"
Lane 3 "DEVOPS": Two boxes: "Review" → "Deploy to Prod"

Arrows flow down from Lane 1 into Lane 2 at "Say ready"
Arrows flow down from Lane 2 into Lane 3 at "Deploy to Dev"

A return arrow from Lane 2 back to Lane 1 labeled "Verify it still works"

At the bottom, the prod deployment box with a star.

The lanes show clear ownership. Your lane is simple. The other two are dense.
```

**Slide Text:**
### The deployment journey: who does what

| Phase | Who | What |
|---|---|---|
| Describe & verify | **You** | Tell /make-it what you want, check it works |
| Ship | **You** | Type `/ship-it` |
| Pre-flight scan | **Automation** | Security, compliance, dependencies, containers |
| Auto-remediation | **Automation** | Fix what's fixable, flag what needs humans |
| Verification | **You** | "Run /try-it -- does it still work?" |
| Dev deployment | **Automation** | Deploy to dev environment |
| Dev testing | **You** | Test in the shared environment |
| Prod gate | **DevOps** | Final review and production deployment |

**You participate at 3 checkpoints. Everything else is automated or handled by DevOps.**

---

## Slide 25 -- /argo-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A transformation diagram.

Left side: A docker-compose.yml file icon (blue) with service labels: "backend",
"frontend", "database"

Center: A magic wand icon or transformation arrow labeled "/argo-it"

Right side: A Kubernetes cluster icon (teal) with the same services now as
small pod icons, connected by service mesh lines.

Below: "Docker Compose → Kubernetes. One command. Zero K8s knowledge."

Small details: "Kustomize manifests", "CI/CD pipeline", "Argo CD GitOps",
"Onboarding docs" floating near the right side as generated artifacts.
```

**Slide Text:**
### /argo-it -- Deploy to Kubernetes without knowing Kubernetes

Your app runs in Docker locally. /argo-it takes it to the cloud.

**What it generates:**
- Kubernetes manifests (dev + prod environments)
- CI/CD pipeline (build, push, deploy on every push)
- Onboarding docs for DevOps (what to configure once)
- Developer docs ("You don't need to know Kubernetes -- just push code")

**How deployment works after setup:**
1. You push code
2. CI builds container images (~1 min)
3. CI mirrors to deploy branch, patches image tags (~30 sec)
4. Argo CD detects changes and syncs (~1 min)
5. **App is live in ~3 minutes. You did nothing but push.**

---

## Slide 26 -- /argo-it: What Gets Generated

**Gemini Image Prompt:**
```
Plain white background, 16:9. An exploded file tree showing generated artifacts:

env/
  dev/
    kustomization.yaml
    deployment.yaml
    service.yaml
    ingress.yaml
  prod/
    kustomization.yaml
    deployment.yaml
    service.yaml
    ingress.yaml

.github/workflows/
  build-and-deploy.yml

ONBOARDING-K8S.md

Each file has a small icon and a one-line description to its right.
The tree communicates completeness -- everything needed for deployment.
```

**Slide Text:**
### /argo-it generates everything DevOps needs

| Artifact | Purpose |
|---|---|
| **env/dev/** | Kubernetes manifests for dev environment |
| **env/prod/** | Kubernetes manifests for production |
| **CI/CD workflow** | GitHub Actions: build, push images, mirror to deploy branch |
| **ONBOARDING-K8S.md** | What DevOps configures once (namespace, secrets, Argo CD) |

**Smart features:**
- Detects your registry, ingress controller, and storage class from existing config
- Asks only what it can't detect (typically 2-3 questions)
- Skips databases and mock services (handled separately in K8s)
- Never hardcodes secrets -- always K8s Secret references
- Pre-build validation catches untracked migrations before they break prod

---

## Slide 27 -- /retrofit-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. Before/after comparison.

LEFT: "Before" -- A simple box labeled "Your Existing App" with a few feature
labels inside: "Pages", "API", "Database". No security, no roles, no Docker.
A yellow caution triangle in the corner.

CENTER: An arrow labeled "/retrofit-it" with sub-labels: "Reverse-engineer →
Gap analysis → Plan → Upgrade → Verify"

RIGHT: "After" -- Same box, same features, but now surrounded by additional
layers: "OIDC Auth" (outer ring), "RBAC Permissions" (ring), "Docker" (ring),
"Security Headers" (ring), "Activity Logs" (ring). Green checkmark in corner.

Below: "Your app. Your design. Now with enterprise foundations."
```

**Slide Text:**
### /retrofit-it -- Upgrade any existing app with enterprise foundations

Have an app already? It doesn't need to be rebuilt. /retrofit-it adds what's missing.

**How it works:**
1. **Reverse-engineers** your app (stack, architecture, features, data model)
2. **Gap analysis** -- compares against /make-it standards, calculates risk score
3. **Plan** -- shows you what will change and what stays the same
4. **Retrofit** -- adds foundations surgically (auth, roles, Docker, security)
5. **Verify** -- runs the same 100+ checks as /make-it

**The #1 rule: never break existing functionality.**

Your app keeps its design, its features, its identity. /retrofit-it adds the enterprise foundation underneath.

---

## Slide 28 -- /retrofit-it: Risk Score

**Gemini Image Prompt:**
```
Plain white background, 16:9. A horizontal risk spectrum bar, colored from green
(left) to amber (center) to coral (right).

Four zones marked on the bar:
0-15: "Low" (green) -- "Single pass, straightforward"
16-35: "Medium" (yellow-green) -- "Single pass, extra verification"
36-60: "High" (amber) -- "Phased retrofit, you verify between phases"
61+: "Very High" (coral) -- "Phased + migration recommendation"

Below the bar, a legend showing change types and their weights:
Add (1) | Enhance (2) | Wrap (3) | Restructure (4) | Replace (5) | Rewrite (8)

Bottom note: "/retrofit-it calculates this automatically and adapts its strategy."
```

**Slide Text:**
### /retrofit-it calculates risk before touching your code

Every gap between your app and the standard is weighted:

| Change type | Risk weight | Example |
|---|---|---|
| **Add** (new, no conflict) | 1 | Adding activity logs |
| **Enhance** (extend existing) | 2 | Adding filters to a data table |
| **Wrap** (adapt what exists) | 3 | Wrapping existing auth with OIDC |
| **Restructure** (move files) | 4 | Reorganizing project structure |
| **Replace** (swap component) | 5 | Replacing auth system |
| **Rewrite** (rebuild module) | 8 | Rewriting from scratch |

**Risk score determines strategy:**
- **0-15:** Low risk, one pass
- **16-35:** Medium, one pass with extra testing
- **36-60:** High, done in phases (you verify between each)
- **61+:** Very high, phased with migration plan

---

## Slide 29 -- /nemo-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A magnifying glass icon (navy) centered, looking
at a document that represents your app. Around the magnifying glass, 6 small
category badges arranged in a circle:

"Prompt Injection" (coral) | "Jailbreak" (rose) | "Toxicity" (amber)
"Topic Boundaries" (purple) | "PII Leakage" (blue) | "Hallucination" (teal)

Below: "60+ test cases. 6 categories. Full attestation report."

A document icon at bottom showing "ATTESTATION-2026-04-02.md" with checkmarks
and X marks suggesting a pass/fail report.

The image communicates thorough, categorized security scanning.
```

**Slide Text:**
### /nemo-it -- AI safety and security attestation

If your app uses AI features, /nemo-it scans it against real attack patterns.

**6 test categories, 60+ test cases:**
- **Prompt injection** -- Can users trick the AI into ignoring instructions?
- **Jailbreak** -- Can users bypass safety boundaries?
- **Toxicity & bias** -- Does the AI produce harmful content?
- **Topic boundaries** -- Does the AI stay within its defined scope?
- **PII leakage** -- Does the AI expose personal information?
- **Hallucination** -- Does the AI make up facts?

**Output:** A dated attestation document -- the proof your AI features are safe.

**/nemo-it reports only. It never changes your code.** That's /fix-it's job.

---

## Slide 30 -- /fix-it

**Gemini Image Prompt:**
```
Plain white background, 16:9. A two-column before/after layout.

LEFT "Before" column: An attestation document with red X marks on some items:
✗ Prompt injection (2 failures)
✗ PII leakage (1 failure)
✓ Jailbreak (pass)
✓ Topic boundaries (pass)
✓ Toxicity (pass)
✓ Hallucination (pass)

CENTER: Arrow labeled "/fix-it"

RIGHT "After" column: Same document, all green checkmarks:
✓ Prompt injection (fixed)
✓ PII leakage (fixed)
✓ Jailbreak (pass)
✓ Topic boundaries (pass)
✓ Toxicity (pass)
✓ Hallucination (pass)

Below: "Read findings → Classify → Auto-fix → Verify → Re-scan → Done."
```

**Slide Text:**
### /fix-it -- Automatically fix security findings

/fix-it reads the most recent /nemo-it attestation and fixes what it can.

**How it works:**
1. **Read** -- Parses the attestation report
2. **Classify** -- Separates auto-fixable from manual-review items
3. **Fix** -- Applies code changes (input sanitization, output validation, etc.)
4. **Verify** -- Starts the app, confirms it still works
5. **Re-scan** -- Runs /nemo-it again to confirm findings are resolved

**Auto-fixable examples:**
- Missing input sanitization → Add sanitizePromptInput()
- AI output rendered unsafely → Switch to escaped rendering
- PII not masked → Add masking before AI provider call

**Manual-review items** get documented with root cause and recommended fix.
