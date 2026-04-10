# Variant Registry

Variants extend the standard /make-it flow with additional design patterns, scaffold overlays, and guardrail checks. They are activated by CLI argument: `/make-it <variant-name>`.

A variant is always layered ON TOP of a base project type. It augments phases (Ideation, Design, Build, Build-Verify) — it never replaces them.

## Available Variants

| Name | File | Base Type | Overlay | Status | Description |
|------|------|-----------|---------|--------|-------------|
| mobile | variants/mobile.md | web-app | overlays/pwa/ | active | PWA with offline support, install prompt, responsive-first layouts |

## Reserved Arguments

These argument values are NOT variant names and are handled separately:
- `update` — triggers the self-update flow

## How Variants Work

1. User types `/make-it mobile`
2. Skill reads this registry, finds "mobile" → loads `variants/mobile.md`
3. During Ideation: variant's extra questions are woven into the conversation
4. During Design: variant's technical decisions are applied silently
5. During Build: variant's scaffold overlay is copied on top of the base scaffold
6. During Build-Verify: variant's additional checks (P01-P08 for mobile) are executed
7. `app-context.json` records `"variant": "mobile"` so downstream skills are aware

## Creating a New Variant

1. Copy `variants/_template.md` to `variants/<your-variant>.md`
2. Fill in all sections (metadata, ideation, design, overlay, guardrails, build-verify)
3. Create scaffold overlay files in `scaffolds/overlays/<your-overlay>/` if needed
4. Add a row to the table above with status `active`
5. Add check IDs to `build-standards.md` for your variant's guardrail checks
