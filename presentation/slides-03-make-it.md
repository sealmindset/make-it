# SECTION 3: /make-it DEEP DIVE

---

## Slide 11 -- /make-it: The 5 Phases

**Gemini Image Prompt:**
```
Plain white background, 16:9. Vertical sequence of 5 numbered circles (1-5)
connected by a thin line, each with icon and label to the right:

1 (slate): Wrench -- "Preflight / Is your machine ready?"
2 (amber): Chat bubble -- "Ideation / What do you want to build?"
3 (blue): Blueprint -- "Design / AI chooses the architecture"
4 (purple): Code brackets -- "Build / 98 files + your features"
5 (green): Checkmark -- "Verify / 100+ checks pass silently"

Left side time labels: "5 min" / "10-15 min" / "invisible" / "20-30 min" / "invisible"

After circle 5, arrow right to browser icon: "Your working app"
```

**Slide Text:**
### /make-it -- 5 phases, ~1 hour, zero coding

| Phase | What happens | Your experience |
|---|---|---|
| **1. Preflight** | Checks tools: Git, Docker, GitHub CLI, VS Code | "All systems go!" |
| **2. Ideation** | You describe your app in plain English | A friendly conversation |
| **3. Design** | AI selects architecture, security model, stack | Invisible -- you see nothing |
| **4. Build** | 98 scaffold files + your custom features | "Building your features..." |
| **5. Verify** | 100+ checks, auth testing, security scan | Invisible -- you see nothing |

**Result: a working app in your browser.**

---

## Slide 12 -- /make-it: The Conversation (Ideation)

**Gemini Image Prompt:**
```
Plain white background, 16:9. Chat conversation mockup, alternating gray (user)
and white-with-green-border (assistant) bubbles:

User: "I want an app to manage training requests for my team"
Assistant: "Who will use this app?"
User: "My department. Managers approve requests."
Assistant: "Should everyone see all requests, or only their own?"
User: "Employees see theirs. Managers see their team's. HR sees everything."

Below the chat, green callout: "From these answers, /make-it designs an app with
3 user roles, approval workflows, and filtered views. No technical decisions needed."
```

**Slide Text:**
### The ideation phase feels like texting a friend

You answer simple questions in plain English:
- "What problem does this solve?"
- "Who uses it?"
- "What should different people be able to do?"
- "Do you need approval workflows?"
- "Any external systems to connect to?"

**No jargon. No forms. No decisions about frameworks or databases.**

From your answers, /make-it silently builds a complete technical blueprint.

---

## Slide 13 -- /make-it: What You Get

**Gemini Image Prompt:**
```
Plain white background, 16:9. 3x3 grid of minimal app page wireframes, each
with a label:

Row 1: "Secure Login" (lock icon, button) | "Dashboard" (cards, chart) | "Data Tables" (rows, filters)
Row 2: "Navigation" (sidebar items) | "User Management" (table, role badges) | "Permission Matrix" (checkboxes)
Row 3: "Activity Logs" (timeline, filters) | "Notifications" (bell, dropdown) | "App Settings" (toggles, groups)

Each wireframe uses accent colors for highlights. Minimal, clean.
Below grid: "Every app includes all of this. Before you add a single feature."
```

**Slide Text:**
### What every /make-it app includes automatically

| Feature | What it means for you |
|---|---|
| **Secure Login** | Only authorized people can access your app |
| **4 User Roles** | Super Admin, Admin, Manager, User -- out of the box |
| **Permission Matrix** | Fine-grained control: who can see and do what |
| **Dashboard** | Visual overview with metrics and charts |
| **Data Tables** | Sortable, filterable, paginated -- like Excel in your browser |
| **Quick Search** | Cmd+K to jump anywhere instantly |
| **Activity Logs** | See who did what and when (10,000 event buffer) |
| **Notifications** | In-app alerts with bell icon and unread badge |
| **App Settings** | Admin-configurable settings without touching code |
| **Dark/Light Mode** | One-click theme toggle |

Then /make-it adds YOUR specific features on top.

---

## Slide 14 -- /make-it: The Invisible Quality Gate

**Gemini Image Prompt:**
```
Plain white background, 16:9. Two panels side by side.

LEFT PANEL "What you see":
Simple progress with checkmarks:
✓ Setting up your project...
✓ Building your features...
✓ Running final checks...
★ "Your app is ready!"

RIGHT PANEL "What actually happens":
Dense vertical list of ~25 items with green dots:
Copy 98 scaffold files / Replace placeholders / Generate domain models /
Create database migrations / Build API endpoints / Wire authentication /
Configure 4 user roles / Set up permissions / Generate frontend pages /
Build dashboard / Create seed data / Configure Docker / Start mock auth /
Run migrations / Seed test data / Test login per role / Verify every API /
Check every page / Validate permissions / Test activity logs / Verify
notifications / Security headers / No hardcoded secrets / Input validation /
Final pass...

The left is calm. The right is dense. Same moment in time.
```

**Slide Text:**
### The invisible quality gate

**What you see:** "Building... Done! Your app is ready."

**What actually happened:**
1. 98 pre-verified files deployed as your foundation
2. Your custom features generated on top
3. Docker containers built and started
4. Database migrations run, test data loaded
5. Login tested for every user role
6. Every API endpoint verified
7. Every page confirmed to load with content
8. Permission boundaries checked (right people see right things)
9. Security scan completed
10. Any failures auto-fixed and retested (up to 3 cycles)

**You never know this happened. That's the point.**

---

## Slide 15 -- /make-it: Build Verify Categories

**Gemini Image Prompt:**
```
Plain white background, 16:9. A grid of 12 category cards (4x3), each a small
rounded rectangle with a colored left border and a title + count:

Row 1: Structure (9 checks, blue) | Auth (10 checks, coral) | RBAC (7 checks, purple) | UI (7 checks, teal)
Row 2: Database (5 checks, amber) | Docker (7 checks, slate) | Mock Services (4 checks, green) | Activity Logs (8 checks, blue)
Row 3: Notifications (8 checks, purple) | Settings (7 checks, amber) | Security (6 checks, coral) | Tests (5 checks, slate)

Center number large and bold: "100+"
Below: "quality checks across 12 categories"

Each card's count is a small badge. The grid communicates breadth and thoroughness.
```

**Slide Text:**
### 100+ quality checks across 12 categories

| Category | What it verifies | # Checks |
|---|---|---|
| **Structure** | Files, .gitignore, README, .env, no stubs | 9 |
| **Authentication** | Login works per role, JWT correct, logout works | 10 |
| **Permissions (RBAC)** | 5 tables, 4 roles, permission checks on every route | 7 |
| **User Interface** | Standard components, system fonts, no hardcoded data | 7 |
| **Database** | Migrations run, seed data correct, users match login | 5 |
| **Docker** | Containers healthy, ports free, health checks pass | 7 |
| **Mock Services** | Auth mock running, seed script works, contracts match | 4 |
| **Activity Logs** | Capturing requests, API works, admin UI functional | 8 |
| **Notifications** | Bell badge, scoped per user, seed data, mark-as-read | 8 |
| **Settings** | Admin page, RBAC gated, graceful fallback | 7 |
| **Security** | No secrets in code, input validation, latest deps | 6 |
| **Tests** | pytest configured, health tests, Playwright scaffolded | 5 |

---

## Slide 16 -- /make-it: The Self-Healing Loop

**Gemini Image Prompt:**
```
Plain white background, 16:9. A circular flow diagram with 4 nodes:

"Build" (purple) → "Check" (blue) → "Fix" (coral) → "Rebuild" (amber) → back to "Check"

The arrow from "Check" splits: one path goes to "Fix" (labeled "fail"), another
goes down to a large green checkmark labeled "Pass → Ship" (labeled "pass").

Small text near the loop: "Up to 3 cycles"
Below the green checkmark: "Only verified apps reach you."

The circular nature shows self-healing. The escape to "Ship" shows the happy path.
```

**Slide Text:**
### Self-healing: build-verify-fix loop

If any of the 100+ checks fail:
1. **Diagnose** -- What went wrong?
2. **Fix** -- Apply the correction automatically
3. **Rebuild** -- Recompile with fresh containers (no stale cache)
4. **Recheck** -- Run all 100+ checks again

This loop runs **up to 3 times**. If it still can't fix something, it stops and explains the issue in plain English.

**Common auto-fixes:**
- Port conflict → Remap to an available port
- Missing seed data → Regenerate migrations
- Auth configuration mismatch → Align JWT with database
- Docker health check failing → Fix IPv6/localhost issue
- API endpoint returning empty → Complete the implementation

**You never see the loop. You only see: "Your app is ready."**

---

## Slide 17 -- /make-it: Types of Apps

**Gemini Image Prompt:**
```
Plain white background, 16:9. Five horizontal cards stacked vertically, each
with an icon, a type name, and a brief description:

1. Browser icon (blue) -- "Web Application" / "The most common. Full app with login, dashboard, data."
2. Extension icon (purple) -- "IDE Extension" / "VS Code plugins and browser extensions."
3. Terminal icon (green) -- "CLI Tool" / "Command-line utilities with --help and exit codes."
4. Package icon (amber) -- "Library" / "Importable packages with type declarations."
5. API icon (teal) -- "API Service" / "Backend-only services that power other apps."

The web application card is slightly larger/highlighted as the primary path.
Below: "Tell /make-it what you need. It picks the right type automatically."
```

**Slide Text:**
### /make-it builds 5 types of applications

| Type | What it is | Example |
|---|---|---|
| **Web Application** | Full app with login, roles, dashboards, data tables | Training request tracker, asset manager |
| **IDE Extension** | VS Code plugin or browser extension | Code review helper, snippet manager |
| **CLI Tool** | Command-line utility | Data migration script, report generator |
| **Library** | Reusable code package | Shared API client, utility functions |
| **API Service** | Backend service with no frontend | Data pipeline, webhook processor |

Each type activates different guardrails and standards automatically.

**Web applications** are the most common -- full enterprise app in ~1 hour.
