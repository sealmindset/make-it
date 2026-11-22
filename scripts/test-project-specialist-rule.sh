#!/usr/bin/env bash
# E11-S1 (the owner's rule, 2026-11-21): one project specialist, recorded by the skills that define the project.
# Fix rounds 1 and 2 (owner decisions D1-D7, review findings F1-F11 and N1-N12, 2026-11-21) are folded in.
#
# WHAT IS PINNED (D5: whole blocks, so an added, removed or changed sentence fails until this test is updated too):
#   - references/expert-personas.md, two blocks: from "## One project specialist" up to "## The persona directive"
#     (the rule, the floor table and how it is filled in, each project specialist's checks, the record and its
#     example, reading older values), and from "## Auto-inference rules" to the end of the file (rules 1-4 with
#     rule 2's order and the variant rank, how a skill invokes this). Compared with the text below after every run
#     of whitespace is folded to one space, so rewrapping a line is not a change.
#   - templates/app-context.md: the expert_persona object in its JSON, and its field-table row, both whole.
# WHAT IS NOT PINNED: the reference's opening lines (the import list is checked separately), the persona directive
#   and the persona catalog; the rest of the template. Text there is unguarded except by the structural checks below
#   and one ban that guards text outside the pinned blocks: the old "cached hint / re-infer each run / stay
#   generalist" wording in the reference, the template, every command file and every user doc.
# STRUCTURAL CHECKS: the import list names exactly the command files that import the reference; the floor table has
#   one row per project_type and the template's project_type table has one row per floor, both ways; the template's
#   and the example's JSON parse as the record (one expert_persona key per file, never a text value, no generalist).
# THE WRITE GUARD: no file but the writers' own pinned step blocks tells the AI to write expert_persona. Scanned:
#   every command file, every text file under .claude/make-it/ except scaffolds/ (app code), this reference and the
#   template, every file under desktop/skills/, and CLAUDE.md. Exempt: only /make-it's Design step block and
#   /retrofit-it's two blocks (its opening block and Discovery step 7); the rest of make-it.md, retrofit-it.md and
#   resume-it.md is scanned. A unit (sentence, list item, table cell or code line) naming expert_persona with a write
#   verb is a write; so is any line with "expert_persona": (a JSON key, inline or not) or expert_persona = (jq or
#   code). "set by" / "recorded by" / "written by" / "updated by" / "re-checked by" naming one of the three writers
#   as a word is provenance, not a write. The <expert_persona> tag several skills carry is a block, not the field.
# A tripwire, not a proof. It cannot catch: a write with a verb not in WRITE; a write split across two sentences; a
# write in a file outside the scanned set; whether a skill really does what the reference says.
# Usage: test-project-specialist-rule.sh [ROOT]. With no ROOT it checks this repo, then runs the controls below on
# edited copies (each with its expected result).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

REF=.claude/make-it/references/expert-personas.md
TPL=.claude/make-it/templates/app-context.md
textfiles() { grep -E '[.](md|py|sh|txt|json|cjs|js|yml|yaml)$|/SKILL[.]md$|refs[.]txt$' | grep -vxF -e "$REF" -e "$TPL" | grep -v '^[.]claude/make-it/scaffolds/' || true; }
if [ -z "${1:-}" ]; then
  CMDS="$(git ls-files '.claude/commands/*.md')"; DOCS="$(git ls-files '.claude/make-it/confluence-docs/*.md' 'desktop/skills/*.md')"
  SCAN="$( { echo "$CMDS"; git ls-files '.claude/make-it/*' 'desktop/skills/*' CLAUDE.md; } | textfiles | sort -u)"
else
  CMDS="$(find .claude/commands -name '*.md' | sort)"; DOCS="$(find .claude/make-it/confluence-docs desktop/skills -name '*.md' 2>/dev/null | sort)"
  SCAN="$( { echo "$CMDS"; find .claude/make-it desktop/skills -type f 2>/dev/null; [ -f CLAUDE.md ] && echo CLAUDE.md; } | textfiles | sort -u)"
fi

flat() { tr '\n' ' ' | tr -s ' ' | sed -E 's/^ +//; s/ +$//'; }
# section FILE START [END]: from the line matching START (included) to the line before END (or the end of the file)
section() { awk -v a="$2" -v b="${3:-}" 'on && b != "" && $0 ~ b {on = 0} $0 ~ a {on = 1} on' "$1"; }
# pin LABEL ACTUAL WANT: the two texts are equal once whitespace is folded; on a difference, show the first one
pin() {
  local a w; a="$(printf '%s' "$2" | flat)"; w="$(printf '%s' "$3" | flat)"
  [ -n "$w" ] || { echo "  $1: the expected block is empty"; return 1; }
  [ "$a" = "$w" ] && return 0
  python3 -I -c 'import sys
a, w = sys.argv[1], sys.argv[2]
i = next((k for k in range(min(len(a), len(w))) if a[k] != w[k]), min(len(a), len(w)))
print(f"  {sys.argv[3]} differs at character {i}:\n    file: ...{a[max(0, i - 60):i + 100]!r}\n    pin:  ...{w[max(0, i - 60):i + 100]!r}")' "$a" "$w" "$1"
  return 1
}

# 1. the reference's two rule blocks and the template's record, whole
read -r -d '' WANT_R1 <<'BLOCK' || true
## One project specialist

Using a specialist and recording one are two separate jobs.

- **One project specialist.** Each project has one project specialist, recorded in the `expert_persona`
  field of `app-context.json`. It is a fact about the project, like its stack: recorded once, and
  updated only when its scope changes (below). The project specialist means the whole record: the
  primary and every added specialist.
- **Who records it.** Only three skills write `expert_persona`: `/make-it` records it at Design,
  `/retrofit-it` records it when it builds `app-context.json` from an existing app, and `/resume-it`
  re-checks it when the project's scope changes (below). No other skill writes it.
- **What changes it.** The project's scope changes when its signals change: a signal added, a signal
  removed, or an unconfirmed signal confirmed or disproved. The writer then works the record out
  again by the same rule, so it can go up or down, never below the floor.
- **Same record or a different one.** Two records are the same when they name the same specialists:
  the same primary and the same added ones, in the same order. The signals' wording does not count.
  A writer that finds the same specialists keeps the existing record exactly as it is, signals and
  dates included, and says nothing. The one edit it makes there is to an unconfirmed signal the new
  evidence settles: a confirmed one loses its `"unconfirmed": true`, and a disproved one is removed.
- **No overwrite without saying so.** No skill overwrites the project specialist without saying so.
  A writer that finds different specialists writes the new record, with its own `set_by` and
  `set_at`, and says so the same way every writer does: one plain line to the user and the same line
  in `CHANGELOG.md`; it asks nothing. The `CHANGELOG.md` line is the history. Each writer's step
  says when its line is said and written.
- **Builders.** `/make-it` and `/resume-it` build the app: they work as the project specialist, the
  whole record, and add no task specialist of their own.
- **Who reads it.** Every other skill that changes or judges code reads the project specialist, then
  adds the specialist its own task needs, the way `/resolve-it` does. For a run, the task specialist
  leads the work and is held to the checks and output standard of every specialist in the record as
  well: that is what working as both means. A run never changes the record. With no record, a skill
  works as its task specialist alone and says nothing.
- **Coordinators.** `/dispatch-it` and `/subagent-it` adopt no specialist themselves; every agent they
  launch on app code is handed the project specialist plus the one its task needs.
- **No app code, no project specialist.** Skills that do not work on an app's code get no project
  specialist.

### Always a named specialist

Every project records a named specialist: "generalist" is not a value and not a rule. The floor is
set by `project_type`:

| `project_type` | Floor specialist |
|---|---|
| `web-app` | Senior full-stack engineer of its stack |
| `api-service` | Senior backend engineer of its stack |
| `cli` | Senior tooling engineer of its language |
| `library` | Senior library maintainer (public API and compatibility) |
| `extension` | Senior extension engineer for its host (the editor or the browser) |

A writer fills in the floor from `stack`: "its stack" is the backend + frontend of a web app (e.g.
"FastAPI + Next.js") and the backend of an API service; "its language" is `stack.language`; "its
host" is the editor or browser the extension runs in.

The floor specialist is always in the record: primary when nothing outranks it, otherwise in `added`
(rule 2 below). Nothing lowers a project below its floor.

A writer sets `project_type` before it records `expert_persona`. With an empty or unknown
`project_type` there is no floor, and no other type's floor is assumed (not the web-app one either):
the writer records nothing until the type is set.

### Each project specialist's checks

This table is the one place each project specialist's checks and output standard live. A skill is
held to the row of every specialist in the record.

| Project specialist | Checks it brings | Output standard |
|---|---|---|
| Application security engineer | attacker mindset: threat model first, then data exposure, authorization and input handling | threat model, fix with a compensating control, rationale an auditor accepts |
| Data engineer / DBA | tenant isolation, indexing, partitioning, migration safety | data model review, safe migration with rollback, load check |
| SRE | SLOs, failure modes, rollback, alerts, behaviour under real traffic | runbook, SLOs, alert rules, tested rollback |
| AI / prompt engineer | evals, prompt drift, red-teaming, model routing | eval suite, prompt governance, red-team set |
| A variant's specialist | the checks its definition file names | the output standard its definition file names |
| Every floor specialist | the conventions, idioms and tests of its stack, language or host; the public API and compatibility for a library | code a senior engineer of that stack would merge: tested, idiomatic, no regressions |

---

## The record

`expert_persona` holds a record, not a text value: the primary specialist, any added ones (security,
reliability, data, ...), the signals that led to each, and which skill set it and when. A signal the
code or the answers could not confirm is marked `"unconfirmed": true`.

Example: a FastAPI + Next.js web app that takes card payments from external customers, recorded by
`/make-it` at Design. Security comes first in the order, so the application security engineer is
primary; external users add SRE; the floor is added last; the expected user count was a guess:

```json
"expert_persona": {
  "primary": {
    "specialist": "Application security engineer",
    "signals": [{ "signal": "features: card payments", "unconfirmed": false }]
  },
  "added": [
    {
      "specialist": "SRE",
      "signals": [
        { "signal": "users.internal_or_external: external", "unconfirmed": false },
        { "signal": "users.estimated_count: thousands", "unconfirmed": true }
      ]
    },
    {
      "specialist": "Senior full-stack engineer of FastAPI + Next.js",
      "signals": [{ "signal": "project_type: web-app (the floor)", "unconfirmed": false }]
    }
  ],
  "set_by": "/make-it",
  "set_at": "2026-11-21"
}
```

**Reading an older value.** A plain text value that names a specialist (an app recorded before this
shape) is read as the primary specialist, with no added specialists and no recorded signals. A text
value that names no specialist ("generalist", "none" or empty), a record whose `primary.specialist`
is empty, and no field at all are each read as no record. A reader never rewrites any of them;
`/resume-it` brings the app up to this shape.

---
BLOCK
read -r -d '' WANT_R2 <<'BLOCK' || true
## Auto-inference rules

The project specialist comes from the `app-context.json` signals, applied by the three writers; the
task specialist comes from the active skill.

1. **Skill sets the task specialist.** `debug-it` → SRE; `nemo-it`/`fix-it` → AppSec;
   `argo-it` → Platform; `retrofit-it` → architect. The builders add none ("Builders" above).
2. **Signals set the project specialist.** Only the three writers apply these, when they record or
   re-check `expert_persona`; every other skill reads the record instead. In order:
   1. Security: payments, personal data (PII) or health data (PHI) in `compliance`, `purpose` or
      `features` → **Application security engineer**.
   2. Data: `multi_tenancy.needed == true`, or the answers describe data at scale → **Data engineer /
      DBA**.
   3. Reliability / platform: `users.internal_or_external == "external"`, `users.estimated_count` in
      the thousands or more, or an uptime promise (an SLA) for production that the user named →
      **SRE**. `deployment.target` holds the cloud provider, not that promise, so the promise is read
      from the answers.
   4. AI: `ai_features.usage_level == "heavy"`, or `ai_features.who_edits_prompts` is not
      `developers` → **AI / prompt engineer**.
   5. Variant: a signal the app's variant names in its definition file under "Project specialist
      signals" → **the specialist it names**. A variant signal that is really a security, data,
      reliability or AI signal takes that signal's rank instead.
   6. The floor for the `project_type`.

   **The order decides the primary.** The highest specialist in this order that applies is primary;
   every other one that applies is added, in this order; the floor specialist is always in the
   record: primary when nothing outranks it, otherwise in `added`. A specialist two signals call for
   appears once, with both signals. A fixed order does not weigh how strong each signal is; that is
   accepted.
3. **Never below the floor.** With no signal firing, the project specialist is the floor for its
   `project_type` (above). There is no generalist fallback.
4. **Record once, read every run.** The three writers record the primary, the added ones and their
   signals in `expert_persona`; every other skill reads it and never works it out again or rewrites
   it.

---

## How a skill invokes this

Near the top of its work, the skill:

1. Reads the project specialist from `expert_persona` in `app-context.json` (no file, or a value
   that reads as no record under "Reading an older value": no record).
2. Adds its task specialist (rule 1) and works as both, as "Who reads it" says. A builder adds none.
3. States both to itself in one line, the task specialist and the specialists in the record, and
   proceeds *in character*, with no user prompt:
   > "Approaching this as an application security engineer on a project whose record names a data
   > engineer and a senior full-stack engineer: threat-model first, then fix."
4. Holds all output to the task specialist's **output standard** (the catalog) and to the output
   standard of every specialist in the record ("Each project specialist's checks"), not a
   generalist's.
5. Writes nothing to `expert_persona` unless it is `/make-it`, `/retrofit-it` or `/resume-it`, and
   then only as the rule above says.

The persona shapes *how* the work is done. It never blocks, never gates, never recommends hiring.
BLOCK
read -r -d '' WANT_TJ <<'BLOCK' || true
  "expert_persona": {
    "primary": { "specialist": "", "signals": [] },
    "added": [],
    "set_by": "",
    "set_at": ""
  },
BLOCK
TROW='| expert_persona | /make-it (Design), /retrofit-it, /resume-it (on a scope change) | The project specialist record (see `references/expert-personas.md`): `primary` and `added` specialists, each with the `signals` that led to it (a signal can be `"unconfirmed": true`), and `set_by` / `set_at`. No other skill writes it. An older plain text value that names a specialist is read as the primary; a text value naming none ("generalist", "none" or empty) or a record with an empty `primary.specialist` means no record. |'
check "the reference's rule block (One project specialist ... The record) is exactly the pinned text" \
  'pin "rule block 1" "$(section "$REF" "^## One project specialist$" "^## The persona directive$")" "$WANT_R1"'
check "the reference's rule block (Auto-inference rules ... the end) is exactly the pinned text" \
  'pin "rule block 2" "$(section "$REF" "^## Auto-inference rules$")" "$WANT_R2"'
check "the template's expert_persona object is exactly the pinned text" \
  'pin "template record" "$(section "$TPL" "^  \"expert_persona\": [{]$" "^  \"skipped_guardrails\"")" "$WANT_TJ"'
check "the template's field row is exactly the pinned text, once" '[ "$(grep -cxF -- "$TROW" "$TPL")" = 1 ]'

# 2. structure
check "the import list names exactly the command files that import the reference" \
  '( want="$(for f in $CMDS; do gq -F "references/expert-personas.md" "$f" && basename "$f" .md; done | sort | tr "\n" " ")";
     got="$(flat < "$REF" | perl -ne "print \$1 if /Imported by (.*?)\./" | grep -oE "\`[a-z-]+\`" | tr -d "\`" | sort | tr "\n" " ")";
     [ "$want" = "$got" ] || { echo "  imports: $want / named: $got"; exit 1; } )'
# types: the project_type values of the reference's floor table, and of the template's classification table
floortypes() { section "$REF" "^[|] \`project_type\` [|] Floor specialist [|]$" "^$" | grep -oE '^[|] `[a-z-]+`' | tr -d '|` ' | sort; }
tpltypes()   { section "$TPL" "^## Project Type Classification" "^## " | grep -oE '^[|][^|]+[|] `[a-z-]+`' | grep -oE '`[a-z-]+`' | tr -d '`' | sort; }
check "the floor table and the template's project_type table name the same types, both ways" \
  '[ -n "$(floortypes)" ] && [ "$(floortypes | tr "\n" " ")" = "$(tpltypes | tr "\n" " ")" ] || { echo "  floor: $(floortypes | tr "\n" " ") / template: $(tpltypes | tr "\n" " ")"; false; }'
# shape FILE HEADING [example]: the first ```json block after HEADING parses and its expert_persona is the record
shape() {
  python3 -I - "$1" "$2" "${3:-}" <<'PY'
import json, re, sys
path, head, example = sys.argv[1], sys.argv[2], sys.argv[3] == "example"
def fail(msg): print(f"  {path}: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
whole = t = open(path, encoding="utf-8").read()
keys = re.findall(r'"expert_persona"\s*:\s*(.)', whole)
if keys != ["{"]: fail(f'"expert_persona": appears {len(keys)} times, starting with {keys}')
if head:
    i = t.find("\n" + head + "\n")
    if i < 0: fail(f"no heading {head!r}")
    t = t[i:]
m = re.search(r"```json\n(.*?)\n```", t, re.S)
if not m: fail("no json block")
src = m.group(1).strip()
doc = json.loads(src if src.startswith("{") else "{" + src + "}")
ep = doc.get("expert_persona")
if not isinstance(ep, dict): fail(f"expert_persona is {type(ep).__name__}, not a record")
if set(ep) != {"primary", "added", "set_by", "set_at"}: fail(f"keys are {sorted(ep)}")
if not isinstance(ep["added"], list): fail("added is not a list")
specs = [ep["primary"]] + ep["added"]
for s in specs:
    if not isinstance(s, dict) or set(s) != {"specialist", "signals"} or not isinstance(s["signals"], list):
        fail(f"a specialist entry is {s!r}")
    if re.search(r"generalist|general-purpose|^\s*none\s*$", s["specialist"], re.I): fail(f"a specialist is {s['specialist']!r}")
    for g in s["signals"]:
        if not isinstance(g, dict) or set(g) != {"signal", "unconfirmed"} or not isinstance(g["unconfirmed"], bool):
            fail(f"a signal entry is {g!r}")
if example:
    if not all(s["specialist"] and s["signals"] for s in specs) or not ep["added"]: fail("the example is not filled in")
    if ep["set_by"] not in ("/make-it", "/retrofit-it", "/resume-it") or not ep["set_at"]: fail("set_by/set_at")
    if not any(g["unconfirmed"] for s in specs for g in s["signals"]): fail("no signal is marked unconfirmed")
    if not any("(the floor)" in g["signal"] for s in specs for g in s["signals"]): fail("the floor is not in the record")
PY
}
check "the template's JSON holds expert_persona once, as the record" 'shape "$TPL" ""'
check "the reference's worked example is that record, filled in, set by a writer, floor included, an unconfirmed signal" 'shape "$REF" "## The record" example'

# 3. the one ban kept: it guards text OUTSIDE the pinned blocks
OLD='cached (default )?hint|re-infer(s|red)? (per|each|every) run|skills re-infer|cache, don.t trust|stays? (a )?(fast |competent )?generalist|generalist is the right|do \*?not\*? force a persona|expert_persona \| [^|]*any skill'
check "(ban outside the pinned blocks) no reference, template, command or user doc keeps the old wording" \
  '( m=0; for f in "$REF" "$TPL" $CMDS $DOCS; do if flat < "$f" | gq -iE -- "$OLD"; then echo "  in $f"; m=1; fi; done; [ "$m" = 0 ] )'

# 4. the write guard
guard() {
  python3 -I - "$@" <<'PY'
import re, sys
WRITE = re.compile(r"\b(record|records|recording|write|writes|writing|written|store|stores|storing|stored|cache|caches|caching|"
                   r"save|saves|saving|saved|update|updates|updating|updated|overwrite|overwrites|overwriting|populate|populates|"
                   r"fill in|fills in|set|sets|setting|change|changes|changing|changed|migrate|migrates|put|puts|putting|replace|"
                   r"replaces|replacing|replaced|assign|assigns|assigned|edit|edits|editing|edited|add|adds|adding|added|append|"
                   r"appends|appending|appended|persist|persists|persisting|persisted|rewrite|rewrites|rewriting|rewrote|rewritten)\b", re.I)
PROV = re.compile(r"\b(set|recorded|written|updated|re-checked) by `?/?(make-it|retrofit-it|resume-it)`?(?=[\s.,;:)]|$)", re.I)
CODE = re.compile(r'"expert_persona"\s*:|\bexpert_persona\s*=')
# each writer's own pinned blocks: (file suffix, start line regex, end line regex) -- removed before the scan
EXEMPT = [("/commands/make-it.md", r"^\*\*Project specialist \(SILENT", r"^\*\*Build the app-context internally"),
          ("/commands/retrofit-it.md", r"^\*\*Adopt the specialist persona before retrofitting", r"^@~/\.claude/make-it/references/expert-personas\.md$"),
          ("/commands/retrofit-it.md", r"^\*\*7\. Project specialist \(SILENT", r"^</step>")]
def units(lines):
    out, cur, fence = [], [], False
    for ln in lines:
        if re.match(r"\s*```", ln): fence = not fence
        if fence or re.match(r"\s*([-*+] |\d+\. |#|```|$)", ln):
            if cur: out.append(" ".join(cur)); cur = []
        cur.append(ln.strip())
    if cur: out.append(" ".join(cur))
    for u in out:
        for cell in u.split("|"):
            for s in re.split(r'(?<=[.!?])["\')]? (?=\S)', " ".join(cell.split())):
                if s.strip(): yield s.strip()
hits = []
for path in sys.argv[1:]:
    try: lines = open(path, encoding="utf-8").read().split("\n")
    except (UnicodeDecodeError, FileNotFoundError): continue
    for suffix, a, b in EXEMPT:
        if ("/" + path).endswith(suffix):
            keep, on = [], False
            for ln in lines:
                if on and re.search(b, ln): on = False
                if not on and re.search(a, ln): on = True
                if not on: keep.append(ln)
            lines = keep
    for n, ln in enumerate(lines, 1):
        if CODE.search(ln): hits.append(f"{path}: code line: {ln.strip()[:160]}")
    for u in units(lines):
        u2 = PROV.sub("", re.sub(r"</?expert_persona>", "", u))
        if "expert_persona" in u2 and WRITE.search(u2): hits.append(f"{path}: {u[:180]}")
for h in hits: print("  writes the field: " + h)
sys.exit(1 if hits else 0)
PY
}
check "no file but the writers' own pinned blocks tells the AI to write expert_persona" 'guard $SCAN'

# 5. controls (this repo only), each with its expected result
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$REF" "$TPL" $CMDS $DOCS $SCAN | tar -xf - -C "$d"; echo "$d"; }
  # edit FILE OLD NEW: in a fresh copy, OLD (literal, whitespace-tolerant; empty = the end of the file) becomes NEW
  edit() { local d; d="$(copy)"; mkdir -p "$d/$(dirname "$1")"; touch "$d/$1"
           O="$2" N="$3" perl -0pi -e '(my $n = $ENV{N}) =~ s/\\n/\n/g; if ($ENV{O} eq "") { $_ .= $n } else { my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$n/ }' "$d/$1"
           if [ -f "$1" ] && cmp -s "$1" "$d/$1"; then echo "  the edit did not apply"; return 2; fi; echo "$d"; }
  fails()  { local d; d="$(edit "$@")" || return 1; ! bash "$SELF" "$d" >/dev/null 2>&1; }
  passes() { local d; d="$(edit "$@")" || return 1; bash "$SELF" "$d" >/dev/null 2>&1 || { bash "$SELF" "$d" | grep -A3 "^FAIL" | head -8 | sed "s|^|    inner: |"; false; }; }
  add() { fails "$1" "$2" "$2$3"; }
  DBG=.claude/commands/debug-it.md
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  # D5: whole blocks -- one harmless sentence inside each pinned block fails; outside, it passes
  check "(control, D5) a harmless sentence added inside rule block 1 fails" 'add "$REF" "Using a specialist and recording one are two separate jobs." " This keeps things tidy."'
  check "(control, D5) a harmless sentence added inside rule block 2 fails" 'add "$REF" "Near the top of its work, the skill:" " (This list is short.)"'
  check "(control, D5) a harmless key added inside the template's record fails" 'add "$TPL" "    \"set_at\": \"\"" ",\n    \"note\": \"\""'
  check "(control, D5) a harmless sentence added outside the pinned blocks (the catalog) passes" 'passes "$REF" "Personas are archetypes; several may apply." "Personas are archetypes; several may apply. This keeps things tidy."'
  # N8: honest sentences outside the pinned blocks now pass
  check "(control, N8) passes: \"\`/demo-it\` and \`/wrap-it\` use no specialist at all.\" (outside the blocks)" \
    'passes "$REF" "\`dispatch-it\` and \`subagent-it\`." "\`dispatch-it\` and \`subagent-it\`. \`/demo-it\` and \`/wrap-it\` use no specialist at all."'
  check "(control, N8) passes: \"No approval is needed.\" (outside the blocks)" 'passes "$REF" "no user question." "no user question. No approval is needed."'
  check "(control, N8) passes: an unrelated \"quietly\" (outside the blocks)" 'passes "$REF" "Personas are archetypes;" "Personas work quietly. Personas are archetypes;"'
  # the 15 reversals from the first review (inside the blocks they fail by the pin; in other files by the guard)
  check "(control R1) fails: a skill may re-infer" 'add "$REF" "No other skill writes it." " A skill may re-infer the project specialist from the signals whenever they look different."'
  check "(control R2) fails: other skills recompute it" 'add "$REF" "No other skill writes it." " Other skills recompute it from the signals on each run and use their result instead."'
  check "(control R3) fails: /make-it and /retrofit-it may replace it quietly" 'add "$REF" "without saying so." " Except: /make-it and /retrofit-it may replace it quietly."'
  check "(control R4) fails: /resume-it asks the user to approve" 'add "$REF" "it asks nothing." " Before changing it, /resume-it asks the user to approve."'
  check "(control R5) fails: a low-risk prototype may use a general-purpose engineer" 'add "$REF" "Nothing lowers a project below its floor." " A low-risk prototype may use a general-purpose engineer instead."'
  check "(control R6) fails: an extra floor row (prototype, no specialist)" 'add "$REF" "for its host (the editor or the browser) |" "\n| \`prototype\` | No specialist (general-purpose) |"'
  check "(control R7) fails: a throwaway script records no specialist" 'add "$REF" "Nothing lowers a project below its floor." " For a throwaway script, record no specialist."'
  check "(control R8) fails: the example's primary is Generalist" 'fails "$REF" "\"specialist\": \"Application security engineer\"" "\"specialist\": \"Generalist\""'
  check "(control R9) fails: security moved below data" 'fails "$REF" "1. Security: payments" "1. Data first, then security: payments"'
  check "(control R10) fails: debug-it puts the persona into expert_persona" 'add "$DBG" "</expert_persona>" "\n\nPut the persona you chose into \`expert_persona\` in app-context.json."'
  check "(control R11) fails: debug-it replaces expert_persona" 'add "$DBG" "</expert_persona>" "\n\nReplace \`expert_persona\` with the persona you chose."'
  check "(control R12) fails: debug-it, passive \"is then updated\"" 'add "$DBG" "</expert_persona>" "\n\nThe \`expert_persona\` field in app-context.json is then updated to the persona you chose."'
  check "(control R13) fails: \"is set by /debug-it\"" 'add "$DBG" "</expert_persona>" "\n\nThe \`expert_persona\` field is set by /debug-it."'
  check "(control R14) fails: a JSON block holding \"expert_persona\": in debug-it" 'add "$DBG" "</expert_persona>" "\n\nThen look at app-context.json:\n\n\`\`\`json\n\"expert_persona\": { \"primary\": {} }\n\`\`\`\n"'
  check "(control R15a) fails: a second \"expert_persona\": \"generalist\" key in the template" 'add "$TPL" "  \"prompts_to_run\": []," "\n  \"expert_persona\": \"generalist\","'
  check "(control R15b) fails: an extra JSON example with the old text value in the template" 'fails "$TPL" "" "\n\`\`\`json\n{ \"expert_persona\": \"Application security engineer\" }\n\`\`\`\n"'
  # round 2: the variant rank (N1), the two-way type check (N7), the import list
  check "(control N1) fails: a variant signal marked security goes first, added to rule 2" 'add "$REF" "takes that signal'\''s rank instead." " A variant signal marked \"security\" goes first instead."'
  check "(control N7) fails: a new project_type in the template with no floor row" 'add "$TPL" "| API Service | \`api-service\` | 0, 5 | Backend only, no frontend, serves other systems |" "\n| Mobile App | \`mobile-app\` | 0, 1 | Phone app |"'
  check "(control) fails: the import list leaves out resolve-it" 'fails "$REF" "\`argo-it\`, \`resolve-it\`," "\`argo-it\`,"'
  # round 2: the guard's bypasses (N4, N9), each now caught; real provenance and the tag still pass
  RES=.claude/make-it/resolve-it/investigator-prompt.md
  check "(control N4) fails: a write in .claude/make-it/resolve-it/investigator-prompt.md" 'fails "$RES" "" "\nStore the chosen persona in \`expert_persona\`.\n"'
  check "(control N4) fails: a write in variants/mobile.md" 'fails .claude/make-it/variants/mobile.md "" "\nRecord the mobile specialist in \`expert_persona\`.\n"'
  check "(control N4) fails: a write in a confluence doc" 'fails .claude/make-it/confluence-docs/04-try-it.md "" "\nThe AI saves its tester role to \`expert_persona\`.\n"'
  check "(control N4) fails: a write in CLAUDE.md" 'fails CLAUDE.md "" "\nUpdate \`expert_persona\` when the app changes.\n"'
  check "(control N4) fails: \"Add ... to \`expert_persona\`\"" 'fails "$RES" "" "\nAdd the SRE to \`expert_persona\`.\n"'
  check "(control N4) fails: append" 'fails "$RES" "" "\nAppend your role to \`expert_persona\`.\n"'
  check "(control N4) fails: persist" 'fails "$RES" "" "\nPersist the role in \`expert_persona\`.\n"'
  check "(control N4) fails: rewrite" 'fails "$RES" "" "\nRewrite \`expert_persona\` with your role.\n"'
  check "(control N4) fails: a jq write" 'fails "$RES" "" "\n    jq \x27.expert_persona = \"SRE\"\x27 app-context.json > tmp\n"'
  check "(control N4) fails: an inline object with \"expert_persona\":" 'fails "$RES" "" "\nWrite { \"stack\": \"x\", \"expert_persona\": \"SRE\" } to app-context.json.\n"'
  check "(control N4) fails: a write in make-it.md outside its Design block" 'add .claude/commands/make-it.md "Stay sequential on shared files." " Then update \`expert_persona\` with the reviewer'\''s pick."'
  check "(control N4) fails: a write in retrofit-it.md outside its two blocks" 'add .claude/commands/retrofit-it.md "**Maximum 3-5 questions. Never more.**" " Then set \`expert_persona\` to the architect."'
  check "(control N9) fails: provenance trick \"set by \`/make-it\`-style logic\"" 'fails .claude/commands/try-it.md "" "\nThe \`expert_persona\` field is set by \`/make-it\`-style logic in /try-it.\n"'
  check "(control N9) fails: a write wrapped across lines (nemo-it)" 'fails .claude/commands/nemo-it.md "**Scan modes**" "Then set\n\`expert_persona\` to the application security engineer.\n\n**Scan modes**"'
  check "(control) passes: provenance naming a real writer (\"set by \`/make-it\` at Design\") in try-it" 'passes .claude/commands/try-it.md "" "\nThe \`expert_persona\` field is set by \`/make-it\` at Design.\n"'
  check "(control) passes: an <expert_persona> tag block with a write verb in try-it (a tag is not the field)" 'passes .claude/commands/try-it.md "" "\n<expert_persona>\nWrite each check as a QA engineer would.\n</expert_persona>\n"'
  check "(control) fails with the old cached hint added outside the blocks (the ban)" 'add "$REF" "no user question." " The optional \`expert_persona\` field is only a cached default hint; skills re-infer per run."'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
