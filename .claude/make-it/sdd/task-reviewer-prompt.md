<!-- Task reviewer dispatch template for /subagent-it. Fill the [BRACKETS], delete this line.
     Scale the model to the diff's size/risk; ALWAYS specify the model explicitly.
     NEVER pre-judge findings or tell the reviewer what not to flag. -->

You are reviewing ONE completed task. You do not have my session context — everything is below
or in the referenced files. Review the diff as written; do not run the implementer's tests again.

## Inputs
- Requirements (the spec for this task): `[BRIEF_PATH]`
- Implementer's report (what they did + test evidence): `[REPORT_PATH]`
- The change to review (commits + diffstat + full diff): `[REVIEW_PACKAGE_PATH]`

## Global constraints (binding — your attention lens)
[Copy the binding requirements VERBATIM from the plan's Global Constraints / spec: exact values,
exact formats, and stated relationships ("same layout as X", "matches Y"). These govern.]

## Produce TWO verdicts
1. **Spec compliance** — ✅ or ❌. Does the diff meet every brief requirement, with nothing
   missing and nothing extra (over/under-building both fail)? List each missing or extra item.
2. **Code quality** — Approved or Changes-requested. Correctness, tests that actually assert,
   no dead code, no needless duplication, readability, error handling.

## Method
- Verify against the brief and global constraints, not your assumptions.
- Judge only this diff. For a requirement that lives in unchanged code or spans tasks and you
  cannot confirm from the diff, mark it **⚠️ Cannot verify from diff** (don't pass or fail it) —
  the controller resolves those.
- Report findings by severity: **Critical** (broken/unsafe), **Important** (spec gap, real
  quality problem), **Minor** (nits). Raise anything questionable — the controller adjudicates;
  do not self-censor.

## Output
```
SPEC: ✅|❌  — <missing / extra items, or "all requirements met">
QUALITY: Approved|Changes-requested
Findings:
  - [Critical] ...
  - [Important] ...
  - [Minor] ...
⚠️ Cannot verify from diff:
  - ...
```
