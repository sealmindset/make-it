# Appendix — AI-Native SDLC Gap Assessment: Source Data

**Generated** 2026-09-23 from commit `5399071` by `docs/scripts/gen-sdlc-gap-appendix.sh`.
**Do not hand-edit.** Re-run the script to refresh.

Companion documents:
- Leadership briefing — `docs/AI-NATIVE-SDLC-GAP-BRIEFING.md`
- Technical companion — `docs/AI-NATIVE-SDLC-GAP-COMPANION.md`

This appendix lists, by name, every file behind every count in those two
documents. It covers **only this repository** (`make-it`). It deliberately omits:

- The contents of generated applications (`/make-it` output lives in other repos).
- Files under `.claude/plugins/` — third-party plugin caches, not this project's code.
- `node_modules`, `.git`, and binary assets.
- Anything requiring GitHub organization or MDM administrator access to observe
  (enterprise managed settings, branch-protection rules, Claude Code admin console
  configuration). Those gaps are stated as *unobserved*, not as *absent*.

---

## A. Skill surface — `.claude/commands`

**Count: 14 skill definition files.**

| File | Size (KB) |
|---|---:|
| `.claude/commands/argo-it.md` | 84 |
| `.claude/commands/clear-it.md` | 7 |
| `.claude/commands/debug-it.md` | 12 |
| `.claude/commands/demo-it.md` | 9 |
| `.claude/commands/dispatch-it.md` | 5 |
| `.claude/commands/fix-it.md` | 22 |
| `.claude/commands/git-it.md` | 4 |
| `.claude/commands/make-it.md` | 75 |
| `.claude/commands/nemo-it.md` | 56 |
| `.claude/commands/resume-it.md` | 60 |
| `.claude/commands/retrofit-it.md` | 55 |
| `.claude/commands/subagent-it.md` | 5 |
| `.claude/commands/try-it.md` | 30 |
| `.claude/commands/wrap-it.md` | 10 |

## B. Shared reference corpus — `.claude/make-it/references`

**Count: 15 reference files, 599 KB total.**

| File | Size (KB) |
|---|---:|
| `.claude/make-it/references/build-standards.md` | 101 |
| `.claude/make-it/references/build-verify-security.md` | 12 |
| `.claude/make-it/references/deployment-profile-architecture.md` | 29 |
| `.claude/make-it/references/deployment-profiles.md` | 34 |
| `.claude/make-it/references/design-blueprint.md` | 157 |
| `.claude/make-it/references/expert-personas.md` | 5 |
| `.claude/make-it/references/fix-strategies.md` | 15 |
| `.claude/make-it/references/git-operations.md` | 7 |
| `.claude/make-it/references/guardrails.md` | 61 |
| `.claude/make-it/references/parallel-dispatch.md` | 7 |
| `.claude/make-it/references/prerequisites.md` | 11 |
| `.claude/make-it/references/prompt-templates.md` | 123 |
| `.claude/make-it/references/ship-it-guide.md` | 28 |
| `.claude/make-it/references/subagent-driven-development.md` | 11 |
| `.claude/make-it/references/worktree-workflow.md` | 6 |

## C. Scaffold inventory — `.claude/make-it/scaffolds`

**Count: 199 files across scaffold trees: fastapi-nextjs, nextjs-fullstack, overlays**

| Scaffold tree | Files |
|---|---:|
| `.claude/make-it/scaffolds/fastapi-nextjs` | 122 |
| `.claude/make-it/scaffolds/nextjs-fullstack` | 67 |
| `.claude/make-it/scaffolds/overlays` | 10 |

---

## D. Gap evidence — greps against .claude/commands and .claude/make-it/references

| Playbook stage | Pattern searched | Matching lines | Files containing it |
|---|---|---:|---|
| Plan / Design | `intent.md` \| `spec.md` \| `plan.md` | 0 | *(none)* |
| Build | `plan mode` \| `EnterPlanMode` \| `ExitPlanMode` | 0 | *(none)* |
| Test | `eval` / `evals` / `evaluation` (prose or otherwise) | 9 | see §E |
| Deploy | `claude-code-action` \| `REVIEW.md` | 0 | *(none)* |
| Maintain | `cycle time` \| `DORA` \| `lead time` \| `telemetry` \| `rolling baseline` \| `Western Electric` | 2 | .claude/commands/nemo-it.md .claude/make-it/references/git-operations.md |

## E. Eval infrastructure

- Files or directories named `eval`/`evals`/`*.eval.json`: **none found**
- Prose mentions of the word (§D, Test row): 9 — these are English usage, not a suite.

## F. Hooks and governance controls

| Control | Observed |
|---|---|
| `.claude/settings.json` present in repo | no |
| `.claude/hooks/` directory present | no |
| Hook event keys (`PreToolUse`/`PostToolUse`/`UserPromptSubmit`/`SessionStart`) in committed settings | 0 |
| Managed-settings keys (`allowManagedHooksOnly`, `disableSideloadFlags`, `permissions.deny`, `sandbox`, `credentials`) in committed settings | 0 |

Committed settings files actually present:
  - `.claude/settings.local.json`

## G. Continuous integration

**Count: 1 workflow file(s).**

  - `.github/workflows/manifest-check.yml`

## H. Policy statements carrying enforcement severity

Severity tags declared across `.claude/make-it/references`:

| Tag | Occurrences | Asserts enforcement | Deterministic enforcer in repo |
|---|---:|---|---|
| `[BLOCK]` | 75 | yes | none — see §F |
| `[FIX]` | 128 | yes | none — see §F |
| **Total asserting enforcement** | **203** | | **none** |
| `[WARN]` | 7 | no (advisory by design) | n/a — correctly advisory |

Each occurrence is a policy the framework states must hold. The `[BLOCK]` and
`[FIX]` tiers assert enforcement; §F shows no hook, no CI check, and no managed
setting implements that enforcement in this repository.

---

*End of generated appendix.*
