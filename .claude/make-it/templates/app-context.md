# App Context Template

This template is populated by /make-it as the user answers questions. It becomes the single source of truth for all prompt generation.

```json
{
  "project_name": "",
  "purpose": "",
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
    "sessions": ""
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
  "deployment": {
    "target": "azure",
    "containerize": false,
    "prototype_only": false
  },
  "pages": [],
  "prompts_to_run": []
}
```

## Field Mapping to Questions

| Field | Gathered During | Question Theme |
|-------|----------------|---------------|
| project_name | Ideation | "What do you want to call your app?" |
| purpose | Ideation | "What problem does it solve?" |
| features | Ideation | "What should it do?" (iterative) |
| users | Ideation | "Who will use it?" |
| auth | Design | Inferred from users.internal_or_external |
| roles | Design | "What types of users?" |
| permissions | Design | "What can each type do?" |
| stack | Design | Inferred from app_type + features |
| multi_tenancy | Design | Inferred from users description |
| ai_features | Ideation + Design | Detected from features keywords |
| ai_features.usage_level | Design | Inferred: none / minimal / moderate / heavy |
| ai_features.prompt_management_tier | Design | 0 (none), 1 (code+config), 2 (db+admin), 3 (full platform) |
| ai_features.who_edits_prompts | Design | developers / product_team / business_users |
| compliance | Design | Only if enterprise/regulated |
| deployment | Design | "Prototype or production?" |
| pages | Design | Derived from features |
