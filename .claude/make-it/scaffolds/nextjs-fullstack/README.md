# Next.js Full-Stack Scaffold

## What This Is

This is the infrastructure scaffold used by `/make-it` when building a web application
with Next.js as both frontend AND backend (API routes). No separate backend service.
This pattern is ideal for internal business tools, CRUD apps, and AI-powered apps
that don't need a separate Python backend.

**Reference implementation:** TPRMAI (AI-powered Third Party Risk Management) was built
with this exact pattern and validated through a complete /retrofit-it cycle.

## When to Use This Scaffold

| Signal | Use This Scaffold | Use fastapi-nextjs Instead |
|--------|-------------------|---------------------------|
| Node.js/TypeScript only | Yes | No |
| AI features using Node SDKs | Yes | No |
| Simple CRUD + dashboards | Yes | No |
| Python AI/ML libraries needed | No | Yes |
| Heavy data processing | No | Yes |
| Need Alembic migrations | No | Yes (SQLAlchemy) |

## Architecture

```
[APP_SLUG]/
├── src/
│   ├── app/
│   │   ├── (authenticated)/       # Route group with shared layout
│   │   │   ├── layout.tsx         # Sidebar + header bar
│   │   │   ├── dashboard/page.tsx
│   │   │   ├── admin/
│   │   │   │   ├── users/page.tsx
│   │   │   │   ├── roles/page.tsx
│   │   │   │   └── prompts/page.tsx  (if AI)
│   │   │   └── [domain pages]/
│   │   ├── api/
│   │   │   ├── auth/
│   │   │   │   ├── login/route.ts
│   │   │   │   ├── callback/route.ts
│   │   │   │   ├── me/route.ts
│   │   │   │   └── logout/route.ts
│   │   │   ├── admin/
│   │   │   │   ├── users/route.ts
│   │   │   │   ├── roles/route.ts
│   │   │   │   └── prompts/route.ts  (if AI)
│   │   │   └── [domain routes]/
│   │   ├── login/page.tsx
│   │   ├── layout.tsx              # Root layout with ThemeProvider
│   │   └── globals.css
│   ├── components/
│   │   ├── layout/sidebar.tsx
│   │   ├── data-table.tsx
│   │   ├── data-table-column-header.tsx
│   │   ├── data-table-toolbar.tsx
│   │   ├── data-table-pagination.tsx
│   │   ├── breadcrumbs.tsx
│   │   ├── quick-search.tsx
│   │   ├── mode-toggle.tsx
│   │   └── theme-provider.tsx
│   ├── lib/
│   │   ├── auth.ts                 # JWT signing, cookie management, getCurrentUser
│   │   ├── auth-context.tsx        # Client-side auth context + useAuth hook
│   │   ├── db.ts                   # Prisma client singleton
│   │   ├── utils.ts                # cn() and other utilities
│   │   ├── prompts.ts              # Prompt loader with cache (if AI)
│   │   └── ai/                     # AI provider abstraction (if AI)
│   │       ├── index.ts            # Factory: reads AI_PROVIDER env var
│   │       ├── provider.ts         # Abstract interface
│   │       ├── model-tier.ts       # Heavy/Standard/Light model selection
│   │       └── providers/
│   │           ├── anthropic-foundry.ts
│   │           ├── anthropic-direct.ts
│   │           ├── openai.ts
│   │           └── ollama.ts
│   └── middleware.ts               # Auth middleware (JWT validation + redirects)
├── prisma/
│   ├── schema.prisma               # Full schema with RBAC + domain tables
│   └── seed.ts                     # Seed data: roles, permissions, users, domain data
├── mock-services/
│   └── mock-oidc/                  # Copied from shared mock-oidc (Python/FastAPI)
│       ├── app.py
│       ├── Dockerfile
│       └── requirements.txt
├── scripts/
│   └── seed-mock-services.sh       # Seeds mock-oidc with test users
├── docker-compose.yml              # App + PostgreSQL + mock-oidc
├── Dockerfile                      # Multi-stage Next.js build
├── entrypoint.sh                   # Prisma migrate + seed on start
├── .env.example                    # All env vars with descriptions
├── .gitignore
├── next.config.js                  # Security headers
├── package.json
├── tailwind.config.ts
├── tsconfig.json
└── postcss.config.mjs
```

## Key Differences from fastapi-nextjs

| Aspect | fastapi-nextjs | nextjs-fullstack |
|--------|---------------|-----------------|
| Backend | FastAPI (Python) | Next.js API routes (TypeScript) |
| ORM | SQLAlchemy + Alembic | Prisma + Prisma Migrate |
| Database | PostgreSQL | PostgreSQL |
| Auth library | authlib (Python) | Custom OIDC with jose (TypeScript) |
| Containers | 4 (frontend, backend, db, mock-oidc) | 3 (app, db, mock-oidc) |
| AI SDK | Python (langchain, anthropic) | Node (@anthropic-ai/sdk, openai) |
| Dockerfile | Separate for frontend + backend | Single multi-stage build |

## Authentication Flow

Same OIDC flow as fastapi-nextjs scaffold, but auth endpoints are Next.js API routes
instead of FastAPI routers. The critical patterns are identical:

- OIDC callback reads role from DATABASE (not OIDC claims)
- JWT payload: { sub, email, name, role_id, role_name, permissions[] }
- Cookie: httpOnly, Secure derived from frontend URL protocol (NOT NODE_ENV)
- Callback redirect uses NEXTAUTH_URL env var (NOT request.url)
- Logout via POST, clears cookie
- Stateless JWT (no server-side sessions)

## RBAC

Prisma schema with 4 tables:
- `roles` (with is_system flag for system roles)
- `permissions` (resource + action, unique constraint)
- `role_permissions` (junction table)
- `users` (with role_id FK and oidc_subject)

Permission checking: `requirePermission(resource, action)` in API routes.
Client-side: `useAuth()` hook with `hasPermission(resource, action)`.

## Placeholders

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `[APP_NAME]` | Human-readable app name | AI TPRM |
| `[APP_SLUG]` | Kebab-case identifier | tprmai |
| `[APP_PORT]` | Host port mapped to container port 3000 | 3020 |
| `[DB_PORT]` | Host port mapped to PostgreSQL port 5432 | 5438 |
| `[MOCK_OIDC_PORT]` | Host port mapped to mock-oidc port 10090 | 10091 |
| `[SEED_USERS]` | JSON array of test users | See fastapi-nextjs README |
| `[DOMAIN_MODELS]` | Prisma models for domain entities | Vendor, Assessment, etc. |
| `[DOMAIN_PAGES]` | App-specific pages to generate | vendors, assessments, etc. |
| `[AI_AGENTS]` | AI agent definitions (if AI) | VERA, CARA, DORA, etc. |

## Status

**SCAFFOLD STRUCTURE DEFINED -- template files to be populated from TPRMAI reference.**

The shared files (mock-oidc, .gitignore, seed script) are copied from the fastapi-nextjs
scaffold. The Next.js-specific template files will be extracted from the TPRMAI codebase
as the reference implementation.
