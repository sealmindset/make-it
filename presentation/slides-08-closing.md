# SECTION 8: CLOSING & CALL TO ACTION

---

## Slide 51 -- The Three Repos

**Gemini Image Prompt:**
```
Plain white background, 16:9. Three boxes in a row, each with a colored top
border and content:

Box 1 (amber top): "make-it"
"Build apps from plain English"
Audience: Everyone
Icon: chat bubble

Box 2 (green top): "ship-it"
"Deploy apps to production"
Audience: Everyone + DevOps
Icon: upload arrow

Box 3 (slate top): "harness-it"
"Test harness for skill validation"
Audience: Skill developers
Icon: test tube

Thin arrows between boxes: make-it → ship-it (deploys), make-it ↔ harness-it (validates)

Below: "Three repos. Clean separation. Each does one thing well."
```

**Slide Text:**
### Three repos, one platform

| Repo | Purpose | Who uses it |
|---|---|---|
| **make-it** | Build apps from plain English | Everyone |
| **ship-it** | Deploy apps to production | Everyone + DevOps |
| **harness-it** | Test harness for skill validation | Skill developers |

**How they connect:**
- /make-it builds apps and generates deployment artifacts
- /ship-it reads those artifacts to deploy
- harness-it validates that make-it's output deploys correctly via ship-it

---

## Slide 52 -- What Types of Apps Can You Build?

**Gemini Image Prompt:**
```
Plain white background, 16:9. A grid of 8 example app cards, each with a small
icon and a title:

Row 1:
- Clipboard icon: "Request Tracker" -- "Track and approve team requests"
- Chart icon: "Reporting Dashboard" -- "Visualize team metrics"
- People icon: "Resource Manager" -- "Manage team assignments"
- Calendar icon: "Event Planner" -- "Coordinate team events"

Row 2:
- Box icon: "Asset Tracker" -- "Track equipment and inventory"
- Checklist icon: "Compliance Checker" -- "Ensure policy adherence"
- Document icon: "Document Portal" -- "Manage team documents"
- Star icon: "Your Idea Here" -- "Describe it. We'll build it."

Each card is minimal with soft colors. The last card has a green glow to suggest
"this is the invitation."
```

**Slide Text:**
### What can you build?

**Any internal web application.** If you can describe it, /make-it can build it.

**Examples:**
- Training request tracker with manager approvals
- Project intake portal with status workflows
- Equipment/asset management system
- Compliance dashboard with audit trails
- Team resource allocation planner
- Vendor onboarding portal
- Internal knowledge base
- Timesheet and expense tracker

**Each one gets:** secure login, user roles, permissions, dashboards, data tables, activity logs, notifications, and settings -- automatically.

---

## Slide 53 -- Before and After: A Real Example

**Gemini Image Prompt:**
```
Plain white background, 16:9. A before/after split.

LEFT "Before /make-it":
A messy spreadsheet icon with annotations:
- "Shared Excel file on Teams"
- "No permissions (everyone can edit)"
- "No audit trail"
- "No approval workflow"
- "Version conflicts"
- "Manual email notifications"

CENTER: Arrow labeled "1 hour with /make-it"

RIGHT "After /make-it":
A clean web app mockup with annotations:
- "Secure web application"
- "Role-based access (view/edit/approve)"
- "Full audit trail"
- "Automated approval workflow"
- "Real-time updates"
- "In-app notifications"

The transformation is dramatic. Messy → polished. Manual → automated.
```

**Slide Text:**
### From shared spreadsheet to secure web app

| | Before | After /make-it |
|---|---|---|
| **Access** | Anyone with the link | Secure login + role-based permissions |
| **Permissions** | Everyone can edit everything | View/Edit/Approve by role |
| **Audit** | No idea who changed what | Full activity log (who, what, when) |
| **Workflow** | Email the manager, hope they reply | Built-in approval workflow with notifications |
| **Versions** | "final_v3_REAL_final.xlsx" | Single source of truth, real-time |
| **Notifications** | Manual emails | In-app alerts + unread badge |
| **Time to build** | N/A (it's a spreadsheet) | ~1 hour |

---

## Slide 54 -- Lessons Learned (Baked Into the Platform)

**Gemini Image Prompt:**
```
Plain white background, 16:9. A grid of lesson cards (3x3), each with a small
coral warning icon and a brief lesson:

"Docker health checks must use 127.0.0.1 (not localhost)"
"External fonts break behind corporate proxies"
"Auth roles must come from database, not identity provider"
"Logout must be POST (browser prefetch triggers GET links)"
"Same-origin proxy required for auth cookies"
"Port conflicts are common -- always check first"
"Mock service contracts must match real API exactly"
"Permission names must match in 5 different locations"
"Database wait in entrypoint must be one-liner (heredoc hangs)"

Below the grid: "Each lesson was a real production bug. Now it's a permanent fix."
```

**Slide Text:**
### Every lesson learned is now a permanent fix

These are real bugs from real builds -- each one is now handled automatically:

| Lesson | How it's fixed |
|---|---|
| Corporate proxies block external fonts | System fonts only, no CDN |
| Docker localhost resolves to IPv6 on some machines | Health checks use 127.0.0.1 |
| OIDC claims change when IT updates the provider | Roles stored in app database, not claims |
| Browser prefetch triggers logout links | Logout is POST-only |
| Cross-origin cookies get blocked | Same-origin proxy built in |
| "Works on my machine" | Docker Compose + mock services |
| Permission visible in sidebar but 403 on API | Naming consistency enforced in 5 locations |
| Users with 2 groups get permissions from only 1 | Multi-role union logic in auth callback |

**You'll never hit these bugs. They're already solved.**

---

## Slide 55 -- FAQ: Common Questions

**Gemini Image Prompt:**
```
Plain white background, 16:9. A clean Q&A layout with 6 questions in two columns,
each with a large "Q" in blue and answer text below:

Q: Do I need to know how to code?
A: No. Zero code required.

Q: How long does it take?
A: About 1 hour from idea to working app.

Q: Is it secure?
A: 100+ security checks, 5 tiers of guardrails.

Q: Can I customize it later?
A: Yes. /resume-it helps add features anytime.

Q: What if I already have an app?
A: /retrofit-it upgrades existing apps.

Q: Who deploys it to production?
A: /ship-it + DevOps automation. You just say "ready."

Clean, minimal, reassuring answers to the obvious questions.
```

**Slide Text:**
### Frequently asked questions

**"Do I need to know how to code?"**
No. You describe what you want in plain English. /make-it handles everything.

**"How long does it take?"**
About 1 hour from idea to a working application.

**"Is it secure?"**
100+ automated security checks, 5 tiers of guardrails, continuous scanning.

**"Can I change it later?"**
Yes. Run /resume-it anytime to add features, fix issues, or work through your to-do list.

**"What if I already have an app?"**
/retrofit-it upgrades existing apps with enterprise foundations without rebuilding them.

**"Who handles deployment?"**
You type /ship-it. Automation and DevOps handle the rest.

**"What if something breaks?"**
The system auto-fixes and retries. If it can't, it explains in plain English.

---

## Slide 56 -- FAQ: For the Technical Audience

**Gemini Image Prompt:**
```
Plain white background, 16:9. Similar Q&A layout but with more technical questions:

Q: What stack?
A: FastAPI + Next.js + PostgreSQL + Docker

Q: What auth protocol?
A: OIDC with configurable provider

Q: How are permissions enforced?
A: require_permission() middleware on every route

Q: Where's the state?
A: JWT in httpOnly cookie, roles from database

Q: Can I see the code?
A: Yes. It's your repo. Full access.

Q: What about CI/CD?
A: GitHub Actions + Argo CD. GitOps pattern.

More technical, more specific, but still concise.
```

**Slide Text:**
### For the technically curious

**"What's the tech stack?"**
FastAPI (Python 3.12) + Next.js 15 + React + Tailwind + PostgreSQL 16 + Docker Compose

**"What auth protocol?"**
OIDC (RFC 6749). Provider configurable: Azure AD, Okta, Auth0, Google, GitHub, Keycloak.

**"How are permissions enforced?"**
`require_permission(resource, action)` on every API route. Frontend gates via `hasPermission()` from JWT.

**"Where's the session state?"**
Stateless. JWT in httpOnly cookie. Roles/permissions queried from database at login, stored in token.

**"Can I see and modify the code?"**
Yes. It's your GitHub repo. Full access. /resume-it helps you make changes.

**"What about CI/CD?"**
GitHub Actions for build/test. Argo CD for GitOps deployment. Kustomize for environment config.

**"What about testing?"**
pytest for backend, Playwright for E2E. Fixtures, auth bypass, health tests scaffolded.

---

## Slide 57 -- Getting Started

**Gemini Image Prompt:**
```
Plain white background, 16:9. Three large numbered steps, each in a rounded box:

Step 1 (amber): Install icon
"Install Claude Code"
"One-time setup, 5 minutes"

Step 2 (blue): Download icon
"Install /make-it"
"Run the install script"

Step 3 (green): Chat icon
"Type /make-it"
"Describe your idea"

Below the steps, a terminal mockup showing:
> /make-it
"What do you want to build today?"

The three steps communicate simplicity. The terminal shows the starting point.
```

**Slide Text:**
### Getting started -- 3 steps, 10 minutes

**Step 1: Install Claude Code** (one-time)
- Available as CLI, desktop app, web app, or IDE extension

**Step 2: Install /make-it** (one-time)
- Run the install script -- copies skills to your machine

**Step 3: Type /make-it** (every time you have an idea)
- Answer questions about your app
- Wait ~1 hour
- See your app running

**That's it. No courses. No training. No prerequisites beyond the tools.**

---

## Slide 58 -- The Invitation

**Gemini Image Prompt:**
```
Plain white background, 16:9. Center of the image, large clean navy text:

"You have the idea."

Below it, in green #10B981:
"/make-it handles the rest."

Below that, generous whitespace, then three small pills in a row:
"98 files" -- "5 tiers" -- "0 code"

Nothing else. Clean, confident, inviting. The simplest slide in the deck.
```

**Slide Text:**
### You have the idea. /make-it handles the rest.

98 pre-built files. 100+ quality checks. 5 security tiers. 9 integrated skills.

**Zero lines of code required.**

14 years of security, development, and DevOps expertise -- working for you, automatically.

Describe what you want. Verify it works. Say "ready."

**That's your entire job.**

---

## Slide 59 -- Contact & Resources

**Gemini Image Prompt:**
```
Plain white background, 16:9. Clean layout with resource links:

A large /make-it logo or text mark at top center.

Three resource cards below:
Card 1: "GitHub" icon -- "sealmindset/make-it" -- "Source code & documentation"
Card 2: "Confluence" icon -- "[Your Confluence space]" -- "Detailed guides & tutorials"
Card 3: "Slack/Teams" icon -- "[Your channel]" -- "Ask questions, share feedback"

Bottom: "Licensed under CC BY 4.0 -- use it, share it, build on it."
```

**Slide Text:**
### Resources

| Resource | What you'll find |
|---|---|
| **GitHub: sealmindset/make-it** | Source code, skill files, scaffold |
| **GitHub: sealmindset/ship-it** | Deployment skill and CI/CD automation |
| **Confluence** | Detailed guides, tutorials, architecture docs |
| **[Your Channel]** | Ask questions, share what you've built |

**License:** CC BY 4.0 -- use it, share it, build on it.

---

## Slide 60 -- Appendix: The Complete Skill Reference

**Gemini Image Prompt:**
```
Plain white background, 16:9. A reference card layout with all 9 skills in a
compact grid:

/make-it: Build new app | 5 phases | ~1 hour
/try-it: Demo app | Auto-start | Screenshots
/resume-it: Continue work | Catch-up | Auto-fix
/wrap-it: Save & exit | Commit | Shutdown
/ship-it: Deploy | PR | CI monitor
/argo-it: K8s deploy | Manifests | GitOps
/retrofit-it: Upgrade existing | Risk score | Phased
/nemo-it: AI security scan | 60+ tests | Attestation
/fix-it: Auto-fix findings | Classify | Re-scan

Each skill is a small card with the accent color and 3 key words.
The grid serves as a quick reference / cheat sheet.
```

**Slide Text:**
### Quick reference: all 9 skills

| Skill | Command | What it does | Time |
|---|---|---|---|
| Build new app | `/make-it` | Idea → working app via Q&A | ~1 hour |
| Demo your app | `/try-it` | Start containers, test, screenshot, report | 2-5 min |
| Continue building | `/resume-it` | Pick up where you left off, catch-up scan | Ongoing |
| Save & shut down | `/wrap-it` | Commit, update docs, stop containers | 1 min |
| Deploy to production | `/ship-it` | Scan, PR, CI monitor, auto-fix | 5-10 min |
| K8s deployment | `/argo-it` | Generate manifests, CI/CD, onboarding | 10-15 min |
| Upgrade existing app | `/retrofit-it` | Reverse-engineer, gap analysis, upgrade | 1-2 hours |
| AI security scan | `/nemo-it` | 60+ tests, 6 categories, attestation | 5-10 min |
| Auto-fix findings | `/fix-it` | Read attestation, fix, verify, re-scan | 5-15 min |
