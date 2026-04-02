# SECTION 6: SECURITY & GUARDRAILS

---

## Slide 38 -- Security: The 5-Tier System

**Gemini Image Prompt:**
```
Plain white background, 16:9. Five horizontal bars stacked vertically, each
a different color and width (wider at top, narrower at bottom to suggest
a pyramid/foundation). Each bar has a tier number, name, and icon:

Tier 0 (slate, widest): "Universal" -- applies to everything (lock icon)
Tier 1 (blue): "Web Application" -- login, roles, Docker (browser icon)
Tier 2 (purple): "IDE Extension" -- VS Code, browser plugins (extension icon)
Tier 3 (green): "CLI Tool" -- command-line utilities (terminal icon)
Tier 4 (amber): "Library" -- reusable packages (package icon)
Tier 5 (teal): "API Service" -- backend services (API icon)

Tier 0 spans the full width (everything gets it). Other tiers activate based
on what you're building.

Below: "Tier 0 is mandatory. The rest activate automatically."
```

**Slide Text:**
### 5 security tiers -- protection scales to what you're building

| Tier | Type | What it enforces |
|---|---|---|
| **Tier 0** | Universal (ALL projects) | No secrets in code, input validation, latest deps, .gitignore, README |
| **Tier 1** | Web Application | OIDC login, RBAC, Docker, mock services, standard UI, activity logs |
| **Tier 2** | IDE Extension | Manifest, activation events, SecretStorage, bundled output |
| **Tier 3** | CLI Tool | Argument parser, --help/--version, exit codes, structured output |
| **Tier 4** | Library | Package manifest, type declarations, public API |
| **Tier 5** | API Service | Health endpoint, OpenAPI spec, structured logging |

**Tier 0 applies to everything you build -- no exceptions.**
Higher tiers activate based on what /make-it detects you're building.

---

## Slide 39 -- Tier 0: What Every Project Gets

**Gemini Image Prompt:**
```
Plain white background, 16:9. A checklist with 4 category headers, each with
sub-items showing green checkmarks:

PROCESS ✓
- Ideation confirmed
- Design documented
- Build verified before handoff

SECURITY ✓
- No secrets in committed files
- No hardcoded config values
- Input validation at system boundaries
- Latest stable dependencies
- No Java runtime dependencies

ARCHITECTURE ✓
- Separation of concerns
- Environment-based configuration
- API-first external communication
- Extensibility by design

QUALITY ✓
- Zero build/compile errors
- CHANGELOG.md from day one
- TODO.md with priorities
- README.md describes the app
- Git initialized with .gitignore

Title: "Tier 0: Universal -- Every project, no exceptions"
```

**Slide Text:**
### Tier 0: What every single project gets -- no matter what

**Process:** Ideation confirmed, design documented, build-verified before handoff

**Security:**
- No secrets in committed files (ever)
- No hardcoded config values (everything from environment)
- Input validation at every system boundary
- Latest stable dependencies (checked for known vulnerabilities)

**Architecture:**
- Clean separation of concerns
- Environment-based configuration
- API-first for external communication
- Extensibility built in from the start

**Quality:**
- Zero build errors
- CHANGELOG.md, TODO.md, README.md from day one
- Git initialized with proper .gitignore

---

## Slide 40 -- Tier 1: Web Application Security

**Gemini Image Prompt:**
```
Plain white background, 16:9. A security architecture diagram for a web app.

Center: "Your Web App" box

Four security layers surrounding it (concentric partial rectangles):

Layer 1 (innermost, blue): "Authentication"
- OIDC single sign-on
- Secure JWT cookies
- CSRF protection (state parameter)

Layer 2 (purple): "Authorization"
- 5 RBAC tables
- Permission checks on every route
- Multi-role with union semantics

Layer 3 (amber): "Monitoring"
- Activity logs (who, what, when)
- Request logging middleware
- Audit trails

Layer 4 (outermost, green): "Hardening"
- Security headers
- Input validation
- No secrets in code
- System fonts (no external CDN)

Each layer wraps around the app, showing defense-in-depth.
```

**Slide Text:**
### Tier 1: Web apps get 4 layers of security

**Layer 1 -- Authentication:**
- OIDC single sign-on (your company's identity provider)
- Secure JWT cookies (Secure flag, httpOnly, proper expiry)
- CSRF protection (cryptographic state parameter)

**Layer 2 -- Authorization:**
- 5 database tables for fine-grained permissions
- `require_permission()` on every single API route
- Multi-role support (permissions are the union of all your roles)

**Layer 3 -- Monitoring:**
- Activity logs capture every request (who, what, when, how long)
- 10,000-event circular buffer with admin UI
- Audit trails for settings changes

**Layer 4 -- Hardening:**
- Security headers (HSTS, CSP, X-Frame-Options)
- Input validation on all endpoints
- Parameterized queries (no SQL injection)
- System fonts only (works behind SSL-inspecting proxies)

---

## Slide 41 -- The Permission Model

**Gemini Image Prompt:**
```
Plain white background, 16:9. A permission matrix visualization.

Top row headers: "View", "Create", "Edit", "Delete"
Left column: "Super Admin", "Admin", "Manager", "User"

The matrix cells have green checkmarks (has permission) or empty (no permission):
Super Admin: ✓ ✓ ✓ ✓ (everything)
Admin: ✓ ✓ ✓ ✗ (no delete)
Manager: ✓ ✓ ✗ ✗ (view + create)
User: ✓ ✗ ✗ ✗ (view only)

Below the matrix, a callout: "This is customizable. Create new roles, assign
any combination of permissions, all through the admin UI."

Small note: "Plus custom roles -- Auditor, Project Lead, Reviewer, anything you need."
```

**Slide Text:**
### The permission model: fine-grained, flexible, database-driven

**4 system roles (created automatically):**

| Role | Default access |
|---|---|
| **Super Admin** | Everything -- manages roles, users, settings |
| **Admin** | Most things -- manages users, views logs |
| **Manager** | Team-level -- sees team data, approves requests |
| **User** | Individual -- sees own data, submits requests |

**But it's not rigid:**
- Create **custom roles** through the admin UI (Auditor, Project Lead, etc.)
- Assign **any combination of permissions** per role
- Users can have **multiple roles** (Manager + Project Lead)
- Permissions are **resource.action** format (projects.read, reports.create)
- **Admin UI permission matrix** -- check the boxes, save, done

---

## Slide 42 -- Build Standards: The Single Source of Truth

**Gemini Image Prompt:**
```
Plain white background, 16:9. A document icon labeled "build-standards.md" at
center, glowing slightly (suggesting importance).

Three arrows emanate from the document to three skill icons:
→ /make-it (amber): "Build-verify runs all checks"
→ /retrofit-it (teal): "Verify phase + preservation checks"
→ /resume-it (purple): "Catch-up scan detects new patterns"

Below the document, a version indicator: "v2.3 -- 100+ checks -- 12 categories"

At the bottom, a key insight: "Update one file. All three skills stay in sync.
Your app never drifts from the standard."
```

**Slide Text:**
### build-standards.md -- one file rules them all

A single document defines what a compliant application looks like. All skills reference it.

| Skill | How it uses the standards |
|---|---|
| **/make-it** | Build-verify runs every check before you see the app |
| **/retrofit-it** | Verify phase runs checks + confirms existing features still work |
| **/resume-it** | Catch-up scan detects new standards added since your last session |

**100+ checks across 12 categories:**
Structure, Auth, RBAC, UI, Database, Docker, Mock Services, Activity Logs, Notifications, Settings, Security, Tests

**Each check has:**
- An ID (S01, A01, R01...) for tracking
- A tier (which project types it applies to)
- A severity: **BLOCK** (must pass), **FIX** (auto-fix), **WARN** (document in TODO)

**When we add new standards, /resume-it detects the gap automatically and upgrades your app.**

---

## Slide 43 -- AI Security (If AI Features Exist)

**Gemini Image Prompt:**
```
Plain white background, 16:9. A flow diagram showing AI request safety:

"User Input" → "Sanitize" (strip injection, wrap in tags) → "Rate Limit Check"
→ "Prompt Assembly" (system prompt + safety preamble + user input) → "AI Provider"
→ "Validate Output" (schema check, XSS scan, range validation) → "Safe Response"

Each step is a box with a small icon. Red stop signs at "Sanitize", "Rate Limit",
and "Validate" suggest checkpoints.

Below the flow, 6 NeMo test categories in small badges:
Injection | Jailbreak | Toxicity | Boundaries | PII | Hallucination

Bottom: "Every AI interaction passes through 6 safety checkpoints."
```

**Slide Text:**
### AI features get their own security layer

If your app uses AI (chatbots, content generation, analysis), /make-it adds:

**Input safety:**
- User input sanitized (injection patterns stripped)
- Wrapped in safe `<user_input>` tags
- Prompt size limits enforced (413 on oversized)

**Provider abstraction:**
- No AI SDK imports in your business code
- Switch providers with one environment variable
- Rate limiting per user (token budget + request count)

**Output safety:**
- Every AI response validated (schema + range checks)
- No unsafe HTML rendering (XSS prevention)
- PII masked before sending to AI provider
- Error messages sanitized (no API keys or model names leaked)

**Prompt management:**
- 6 database tables, admin UI for editing prompts
- Version history with one-click restore
- Draft → Test → Publish workflow
- Immutable safety preamble (can't be edited out)

---

## Slide 44 -- The Scan-Fix-Verify Loop

**Gemini Image Prompt:**
```
Plain white background, 16:9. A circular flow with 4 nodes:

"Build" (purple) → "Scan" (blue, /nemo-it) → "Fix" (coral, /fix-it) →
"Verify" (green, /try-it) → back to "Scan"

An exit arrow from "Verify" goes to "Ship" (green flag) labeled "All clear"

Center of the circle: "Continuous security"

Below the circle, a timeline showing when each scan happens:
"Build time" (/make-it build-verify) → "Pre-ship" (/ship-it scan) →
"Runtime" (security scanner) → "Next session" (/resume-it catch-up)

The message: security isn't one-time. It's continuous across the entire lifecycle.
```

**Slide Text:**
### Security is continuous, not one-time

| When | What scans | Who fixes |
|---|---|---|
| **Build time** | /make-it build-verify (100+ checks) | /make-it (automatic) |
| **Pre-ship** | /ship-it pre-push review (lint, secrets, deps) | /ship-it (automatic) |
| **AI safety** | /nemo-it (60+ test cases, 6 categories) | /fix-it (automatic) |
| **CI pipeline** | DevOps automation (security, compliance, containers) | Automation + DevOps |
| **Runtime** | Security scanner (continuous) | /resume-it (automatic) |
| **Next session** | /resume-it catch-up (new standards) | /resume-it (automatic) |

**The user's experience:** "I made some security updates. Run /try-it to check everything still works."

**That's it. You verify behavior. The system handles security.**
