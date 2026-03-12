# App Context Template

This template is populated by /make-it as the user answers questions. It becomes the single source of truth for all prompt generation and guardrail activation.

```json
{
  "project_name": "",
  "purpose": "",
  "project_type": "",
  "active_tiers": [0],
  "features": [],
  "users": {
    "description": "",
    "types": [],
    "estimated_count": "",
    "internal_or_external": ""
  },
  "auth": {
    "needed": false,
    "provider": "",
    "session_length": "8 hours"
  },
  "roles": [],
  "permissions": {},
  "stack": {
    "frontend": "",
    "backend": "",
    "database": "",
    "orm": "",
    "validation": "",
    "sessions": "",
    "language": "",
    "build_tool": "",
    "runtime": ""
  },
  "app_type": "",
  "multi_tenancy": {
    "needed": false,
    "tenant_type": ""
  },
  "ai_features": {
    "needed": false,
    "description": "",
    "usage_level": "none",
    "prompt_count_estimate": 0,
    "prompts": [],
    "agents": [],
    "models": [],
    "who_edits_prompts": "developers",
    "prompt_management_tier": 0
  },
  "compliance": [],
  "special_features": [],
  "mock_services": {
    "mock_oidc": {
      "needed": false,
      "port": 3007,
      "test_users": []
    },
    "mock_github": {
      "needed": false,
      "port": 3006
    },
    "mock_cribl": {
      "needed": false,
      "port": 3005
    },
    "mock_jira": {
      "needed": false,
      "port": 8443
    },
    "mock_tempo": {
      "needed": false,
      "port": 8444,
      "requires": "mock_jira"
    },
    "custom_mocks": []
  },
  "integrations": [],
  "deployment": {
    "target": "azure",
    "containerize": false,
    "prototype_only": false
  },
  "pages": [],
  "prompts_to_run": [],
  "skipped_guardrails": {}
}
```

## Project Type Classification

| Type | `project_type` value | Active Tiers | Signals |
|------|---------------------|-------------|---------|
| Web Application | `web-app` | 0, 1 | Frontend + backend, browser UI, login, dashboards, CRUD |
| IDE Extension | `extension` | 0, 2 | VS Code plugin, editor tooling, browser extension |
| CLI Tool | `cli` | 0, 3 | Command-line, terminal, no GUI |
| Library / Package | `library` | 0, 4 | Importable, no standalone runtime |
| API Service | `api-service` | 0, 5 | Backend only, no frontend, serves other systems |

The `active_tiers` array determines which guardrails from `guardrails.md` are enforced. Tier 0 is always included.

## Field Mapping to Questions

| Field | Gathered During | Question Theme |
|-------|----------------|---------------|
| project_name | Ideation | "What do you want to call your app?" |
| purpose | Ideation | "What problem does it solve?" |
| project_type | Design | Auto-classified from ideation answers (user never sees this) |
| active_tiers | Design | Auto-set from project_type |
| features | Ideation | "What should it do?" (iterative) |
| users | Ideation | "Who will use it?" |
| auth | Design | Inferred from users.internal_or_external |
| roles | Design | "What types of users?" |
| permissions | Design | "What can each type do?" |
| stack | Design | Inferred from app_type + features + project_type |
| multi_tenancy | Design | Inferred from users description |
| ai_features | Ideation + Design | Detected from features keywords |
| ai_features.usage_level | Design | Inferred: none / minimal / moderate / heavy |
| ai_features.prompt_management_tier | Design | 0 (none), 1 (code+config), 2 (db+admin), 3 (full platform) |
| ai_features.who_edits_prompts | Design | developers / product_team / business_users |
| integrations | Ideation | Detected from features (Jira, Oracle, Tempo, etc.) |
| mock_services | Design | Auto-determined: mock_oidc if auth, mock_jira/mock_tempo/mock_github/mock_cribl if matching integration, custom mocks for others |
| mock_services.custom_mocks | Design | One entry per integration without a ready-made mock: { name, port, endpoints_needed } |
| compliance | Design | Only if enterprise/regulated |
| deployment | Design | "Prototype or production?" |
| pages | Design | Derived from features |
| skipped_guardrails | Design | Documents why non-active-tier guardrails were skipped |

## Skipped Guardrails Documentation

The `skipped_guardrails` object records which higher-tier guardrails don't apply and why:

```json
{
  "skipped_guardrails": {
    "oidc_auth": "Project is a VS Code extension -- auth handled via API token in settings, not OIDC",
    "database_rbac": "No database -- extension uses VS Code settings and server API for configuration",
    "docker_compose": "VS Code extensions run in the editor runtime, not containers",
    "seed_data": "No database to seed",
    "standard_ui_components": "Extension uses VS Code TreeView and DiagnosticCollection, not web UI components"
  }
}
```

This creates an explicit audit trail of design decisions, preventing silent guardrail omission.
