---
name: nemo-it
description: Report-only security scan of code the user shares in Claude Desktop or Cowork, against the OWASP Testing Guide and NeMo Guardrails AI safety checks. Runs what the sandbox can do by reading the files (code pattern checks, static analysis, dependency audit when network allows, AI safety wiring checks) and writes a plainly labeled static attestation that lists every live test it did not run. Never changes the user's code. In Claude Code, use /nemo-it instead.
---

# nemo-it (Claude Desktop / Cowork)

**Running in Claude Code?** If you have a real shell with Docker and git on the user's machine,
stop here and tell the user to run `/nemo-it` instead.

The full scan is `references/nemo-it.md`. Follow it, with the overrides below. Where the two
disagree, this file wins. Paths in the references that start with `claude-code:` exist only in
a Claude Code install. They are not available here.

## Report only (absolute)

The "What you NEVER do" list and the guardrails in `references/nemo-it.md` stand as written.
You never change the user's code, configuration, or dependencies, even if they ask. The only
files you write are the attestation (plus JSON or JUnit if asked for). If the user wants the
findings addressed, point them to their development team, or offer the `handoff` skill so
Claude Code can take it from there (its `/fix-it` works from this attestation).

Never use keys, tokens, or passwords found in the user's files for anything.

## Where the files are

Check what you can do; do not assume:
- **You can read and write a folder the user picked (Cowork):** scan the project there and write
  the attestation to `docs/attestations/nemo-it/YYYY-MM-DD-vN.md` in that folder. Increment `N`
  if earlier attestations for the same day exist.
- **Otherwise (Desktop chat sandbox):** scan what the user uploaded and give them the attestation
  as a downloadable file. Use `v1` unless they tell you about an earlier one.

## What runs here

| Mode | Runs here | NOT RUN here |
|---|---|---|
| `sast` | Phase 1 code pattern checks (always). Semgrep, Bandit, ESLint security only if the tool is present, or can be installed with network access and the user's OK. | Any tool not available. |
| `deps` | `npm audit` (needs `package-lock.json`) and `pip-audit -r <requirements file>` if network allows. `trivy fs` / `trivy config` if trivy is present and network allows (it downloads its vulnerability database). | Trivy image scans, anything that needs `docker`, license check without installed packages, every audit when there is no network. |
| `owasp` | OWASP test cases whose question can be answered by reading the code: cookie flags, security headers, CORS, error handlers, auth and access checks, query building, output encoding. | Every test case that needs a running app: ZAP, pytest or Playwright against the app, SQLMap. |
| `guardrails` | Phase 3 code-level checks 1-9 (prompt construction, input sanitization, output validation and handling, rate limiting, PII masking, error sanitization, system prompt, prompt size). | Check 10 (API probing) and all six behavioral test categories. |
| `full` | All of the above. | All of the above. |

Say which mode you are running and what it leaves out before you start.

## Overrides by step

| nemo-it.md | In Desktop |
|---|---|
| preflight 1 | Say you will read their files and not run their app, and that you will not change anything. |
| preflight 2 | Take the mode and any `--format` from the user's words. No mode given means `full`. |
| preflight 5 (running app) | Skip. Do not probe localhost, and do not offer to start the app. Dynamic analysis is NOT RUN. |
| preflight 6 (production) | Check the project's `.env` files as written. Skip the `echo` lines: they show the sandbox's settings, not theirs. |
| preflight 7 (tools) | Tools go in the sandbox, not on the user's machine. The consent rule still holds. Never install ZAP, SQLMap, Playwright, NeMo Guardrails, or anything with `brew` or `docker pull`: they only serve checks that cannot run here. |
| Phase 1.5 item 2 (pip-audit) | Always pass the requirements file. Plain `pip-audit` audits the sandbox's own packages, not the project's. |
| Phase 2 (dynamic analysis) | NOT RUN, all of it. Record: "Dynamic analysis was not run: this is a static attestation made in a Claude Desktop sandbox. It needs a running app." You may still review the code for the same concern (for example, cookie flags set in code). Record a missing control as a finding with file and line. Record a present control as "present in code, not verified live". |
| Phase 3 check 0 and important reminder 10 | Code-level mode only, whatever keys the `.env` holds. Replace the "PASS (code-level)" label with **CONTROLS PRESENT IN CODE (static; not behavior-tested)**, and replace its note with: "Behavioral testing was not run. It needs a live AI provider and a running app." |
| Phase 3 test categories 1-6 and step 8 | Do not send any of the test prompts anywhere. Each category is NOT RUN (or N/A when no AI features were found). Do not use the "[X/10 passed]" update. |
| Phase 4 item 3 (executive summary) | Label the posture rating "based on static review only". |
| Phase 4 item 4 (OWASP Top 10 mapping) | Status is FAIL, NO FINDINGS (static only), or NOT RUN. Never PASS for a category that depends on live testing. |
| Phase 4 item 6 | `design-blueprint.md` is not available here. Classify against `references/guardrails.md` alone. |
| Important reminders 3 and 9 | Do not apply. Nothing live is scanned. |

## The attestation must say what didn't happen

Use Phase 5 and `references/nemo-it-attestation.md` as written, except:

1. **First line under the title:** "**Static / sandbox attestation.** This scan read the
   project's files in a Claude Desktop sandbox. It did not run the application, call any live
   endpoint or AI provider, or scan container images. The checks under Not Run were not
   performed and are not passed."
2. **Add a `## Not Run (Deferred)` section** right after the Executive Summary. List every check
   that did not run, one line each with the reason: dynamic analysis, each behavioral AI
   category, Phase 3 check 10, container image scans, and any tool or audit that was missing
   or had no network.
3. **Status values:** everywhere the template or `references/owasp-testing-guide.md` (Reporting)
   offers PASS / FAIL / NA / DETECT-ONLY, also use **NOT RUN**. A category or suite is PASS
   only if every one of its tests ran here and none failed. If only some ran and found
   nothing, write NO FINDINGS (static only).
4. **Phase 5 "Scan Coverage" table:** use `Completed (static)`, `Partial (static only)`, or
   `NOT RUN (sandbox)` instead of `Completed/Skipped/App Not Running`. Set Target to "none
   (no live target)" and Environment to "Claude Desktop sandbox (static)". "Tools used" lists
   only the tools that actually ran, with versions.
5. **Template header, Summary Dashboard, Test Environment Details:** Environment and Assessed By
   say "Claude Desktop sandbox (static)" and "nemo-it (make-it-desktop)". Add a "Categories not
   run" row to Key Metrics, and count only fully run categories as passed. Dashboard rows 1-6
   (NeMo behavioral) and row 20 (Trivy container) are NOT RUN, or N/A if no AI features were
   found. Target URL, Container Image, Image Digest, and CI Pipeline Run are "none (static
   scan)".
6. **Per-category blocks:** Tests Run and Tests Passed count only tests that ran here.
7. **Appendix A and "Attestation Metadata":** mark tools that did not run as "not run". Add
   "No live tests were run." after the safe-testing line.
8. **Phase 5 step 4 summary to the user:** after the findings, list what was not run in plain
   words. If the user wants those checks done, offer the `handoff` skill; its deferred checks
   are the Not Run list.
