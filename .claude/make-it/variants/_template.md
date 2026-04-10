# Variant: [VARIANT_NAME]

## Metadata

- **Name:** [name used in `/make-it <name>`]
- **Base project type:** web-app | extension | cli | library | api-service
- **Scaffold overlay:** overlays/[name]/ (or `null` if no overlay files needed)
- **Extends tiers:** [list of tier numbers this variant adds checks to, e.g., 0, 1]
- **Composable with:** [list of other variant names, or "none"]

---

## Ideation Additions

Additional questions to ask during ideation. These are woven conversationally into the standard ideation flow — NOT asked as a separate block after standard questions.

1. **[Question theme]:** "[Plain-language question to ask the user]"
   - Follow-up if yes: "[Follow-up question]"
   - Maps to app-context field: `variant_config.[field_name]`
   - Values: [list of possible values]

---

## Design Additions

Additional decisions made silently during the Design phase (user never sees these):

- **[Decision area]:** [How to decide based on ideation answers] → records `variant_config.[field]`

---

## App-Context Additions

New fields added to `app-context.json` when this variant is active:

```json
{
  "variant": "[name]",
  "variant_config": {
    // variant-specific fields here
  }
}
```

---

## Scaffold Overlay

### New files (from overlay directory)

Files in `~/.claude/make-it/scaffolds/overlays/[name]/` that are copied into the project after the base scaffold:

| File | Purpose |
|------|---------|
| `path/to/file` | What it does |

### Base scaffold modifications

Instructions for modifying existing base scaffold files. These are instructions for Claude to follow during Build, not file patches:

| Base File | What to Change |
|-----------|---------------|
| `path/to/base/file` | Description of what to add/modify and why |

---

## Guardrail Additions

New guardrail checks specific to this variant. Use a unique prefix for check IDs (e.g., P for PWA, E for Electron, C for Chrome extension).

Format: `[Tier N+variant_name]` — these are additive to the base tier's guardrails.

| ID | Tier+Variant | Severity | Check | Description |
|----|-------------|----------|-------|-------------|
| X01 | [Tier N+name] | [BLOCK/FIX/WARN] | Check name | What to verify |

---

## Build-Verify Additions

Additional checks to run during build-verify when this variant is active.

### Static checks (Part A)

Checks that can be verified by reading files without running the app:

- [ID]: [What to check and how]

### Live checks (Part B)

Checks that require the app to be running:

- [ID]: [What to check and how]

---

## Build Standards Additions

Check IDs to add to `build-standards.md`. These use the same format as existing checks but with the `[Tier N+variant_name]` qualifier so they only activate for projects using this variant.

| ID | Tier+Variant | Severity | Check | Description |
|----|-------------|----------|-------|-------------|
| X01 | [Tier N+name] | [BLOCK/FIX/WARN] | Check name | Full description of what must be true |
