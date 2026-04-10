# App Context Template

This template is populated by /make-it as the user answers questions. It becomes the single source of truth for all prompt generation and guardrail activation.

```json
{
  "project_name": "",
  "purpose": "",
  "project_type": "",
  "variant": null,
  "variant_config": {},
  "active_tiers": [0],
  "scaffold": null,
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
    "token_expiry": "8 hours"
  },
  "roles": [],
  "permissions": {},
  "stack": {
    "frontend": "",
    "backend": "",
    "database": "",
    "orm": "",
    "validation": "",
    "auth_tokens": "stateless-jwt",
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
  "ai_providers": {
    "needed": false,
    "primary": "",
    "fallback": "",
    "model_tiers": {
      "heavy": "",
      "standard": "",
      "light": ""
    },
    "provider_config": {
      "anthropic_foundry": {
        "endpoint": "",
        "uses_default_credential": true,
        "note": "No API key -- uses DefaultAzureCredential (managed identity / az login)"
      },
      "anthropic": {},
      "openai": {},
      "ollama": {
        "base_url": "http://localhost:11434"
      }
    }
  },
  "nemo_guardrails": {
    "enabled": false,
    "version": "latest",
    "attestation_mode": "snapshot",
    "categories": [
      "prompt_injection",
      "jailbreak",
      "toxicity_bias",
      "topic_boundaries",
      "pii_leakage",
      "hallucination"
    ],
    "topic_domain": "",
    "last_run": "",
    "last_result": ""
  },
  "compliance": [],
  "special_features": [],
  "mock_services": {
    "mock_oidc": {
      "needed": false,
      "host_port": 3007,
      "container_port": 10090,
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
  "cloud": {
    "provider": "",
    "region": "",
    "cli_authenticated": false
  },
  "deployment": {
    "target": "",
    "containerize": false,
    "prototype_only": false
  },
  "security_scanner": {
    "type": "",
    "api_url": "",
    "uses_github_issues": false
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

## Scaffold Selection

The `scaffold` field determines whether the Build phase uses a pre-built scaffold or generates from scratch.

| Condition | `scaffold` value | Build strategy |
|-----------|-----------------|----------------|
| `web-app` + Python backend | `"fastapi-nextjs"` | Copy scaffold, replace placeholders, generate domain code on top |
| `web-app` + Node.js full-stack (API routes) | `"nextjs-fullstack"` | Copy scaffold, replace placeholders, generate domain code on top |
| `web-app` + Python backend + variant | `"fastapi-nextjs"` | Copy scaffold + variant overlay, replace placeholders, generate domain code on top |
| All other combinations | `null` | Generate from prompt-templates.md (Prompts #1-#14) |

When `scaffold` is set, the Build phase skips generating auth, RBAC, Docker, mock-oidc, and standard UI components — these come pre-built from the scaffold. Only domain-specific code is generated fresh.

## Field Mapping to Questions

| Field | Gathered During | Question Theme |
|-------|----------------|---------------|
| project_name | Ideation | "What do you want to call your app?" |
| purpose | Ideation | "What problem does it solve?" |
| project_type | Design | Auto-classified from ideation answers (user never sees this) |
| variant | Argument parsing | Set from `/make-it <variant>` argument; null if no argument. See `variants/registry.md` |
| variant_config | Ideation + Design | Variant-specific questions and decisions; empty object if no variant |
| active_tiers | Design | Auto-set from project_type |
| scaffold | Design | Auto-set: `"fastapi-nextjs"` for web-app + Python backend, `"nextjs-fullstack"` for web-app + Node.js full-stack, `null` otherwise |
| features | Ideation | "What should it do?" (iterative) |
| users | Ideation | "Who will use it?" |
| auth | Design | Inferred from users.internal_or_external |
| auth.provider | Design | Valid values: "azure-ad" \| "auth0" \| "okta" \| "google" \| "github" \| "keycloak" \| "other" \| "" |
| roles | Design | "What types of users?" |
| permissions | Design | "What can each type do?" |
| stack | Design | Inferred from app_type + features + project_type |
| multi_tenancy | Design | Inferred from users description |
| ai_features | Ideation + Design | Detected from features keywords |
| ai_features.usage_level | Design | Inferred: none / moderate / heavy (minimal is eliminated -- minimum is moderate) |
| ai_features.prompt_management_tier | Design | 0 (none -- no AI), 2 (db+admin -- MINIMUM for any AI app), 3 (full platform) |
| ai_features.who_edits_prompts | Design | developers / product_team / business_users |
| ai_providers | Design | Auto-determined when ai_features.needed is true |
| ai_providers.primary | Design | Inferred from cloud.provider + enterprise context: "anthropic_foundry" \| "anthropic" \| "openai" \| "ollama" |
| ai_providers.model_tiers | Design | Inferred from ai_features.agents complexity; defaults to latest Claude models |
| nemo_guardrails.enabled | Design | Auto-set to true when ai_features.needed = true |
| nemo_guardrails.attestation_mode | Design | "snapshot" (default, versioned per run) or "latest" (overwrite each /ship-it) |
| nemo_guardrails.topic_domain | Design | Inferred from project purpose -- defines the AI's allowed scope (e.g., "vendor risk management") |
| integrations | Ideation | Detected from features (Jira, Oracle, Tempo, etc.) |
| cloud.provider | Design | "Where would you like to host this?" (Azure, AWS, Google Cloud, or just local) -- values: "azure" \| "aws" \| "gcp" \| "none" |
| cloud.region | Design | Inferred from provider choice or asked |
| mock_services | Design | Auto-determined: mock_oidc if auth, mock_jira/mock_tempo/mock_github/mock_cribl if matching integration, custom mocks for others |
| mock_services.custom_mocks | Design | One entry per integration without a ready-made mock: { name, port, endpoints_needed } |
| compliance | Design | Only if enterprise/regulated |
| deployment.target | Design | Populated from cloud.provider during Design |
| security_scanner.type | Design / Enterprise config | Auto-detected from environment or asked in enterprise contexts -- values: "auditgithub" \| "github-advanced-security" \| "snyk" \| "sonarqube" \| "none" \| "" |
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
