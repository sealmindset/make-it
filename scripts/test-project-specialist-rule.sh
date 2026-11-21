#!/usr/bin/env bash
# E11-S1 (the owner's rule, 2026-11-21): one project specialist, recorded by the skills that define the project.
# Fix round 1 (owner decisions D1-D4 and review findings F1-F11, 2026-11-21) is folded in.
# Contract these checks pin (references/expert-personas.md and templates/app-context.md, as the agent reads them):
#   - Using a specialist and recording one are two separate jobs. One project specialist, a fact about the project
#     recorded in app-context.json's expert_persona, written only by /make-it (Design), /retrofit-it and /resume-it
#     (on a scope change). Every writer that replaces a record says so the same way (one line to the user and in
#     CHANGELOG.md), asking nothing. Scope = the signals: one added, removed, or an unconfirmed one settled; the record
#     can go up or down, never below the floor. Every skill that changes or judges code reads it and adds its task
#     specialist, which leads the run held to the project specialist's standard; a run never changes the record.
#   - D1: a fixed order decides the primary (security, data, reliability/platform, AI, the floor); the floor
#     specialist is always in the record. Only the three writers apply the signals.
#   - Always a named specialist: the floor per project_type, row by row, exactly five rows; an unknown type gets none.
#   - The record's shape, in the template's JSON and in the reference's worked example (no "Generalist" value, one
#     expert_persona key each); a text value naming no specialist, or an empty primary, reads as no record.
#   - None of the old wording is back, and targeted bans hold in the reference (re-infer, recompute, general-purpose,
#     "no specialist" as a value, quietly, approval, highest-risk).
#   - No file but make-it.md, retrofit-it.md and resume-it.md tells the AI to write the field. Scanned: command
#     files, references/*.md (not this rule), the SDD prompt templates, desktop/skills. A JSON line holding
#     "expert_persona": is a write. "set by" / "recorded by" is allowed only when it names one of the three writers.
#     The XML-style <expert_persona> block several skills carry is a tag, not the field, and is not counted.
# A tripwire, not a proof, and no rule is added per bypass. It cannot catch: a write said with a verb not in WRITE; a
# write split across two sentences; a write in a file outside the scanned set; whether a skill really does what the
# reference says.
# Usage: test-project-specialist-rule.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# their opposites (and pass on a tag that is not a write, and on provenance naming a real writer).
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
if [ -z "${1:-}" ]; then
  CMDS="$(git ls-files '.claude/commands/*.md')"; DOCS="$(git ls-files '.claude/make-it/confluence-docs/*.md' 'desktop/skills/*.md')"
  MORE="$(git ls-files '.claude/make-it/references/*.md' '.claude/make-it/sdd/*.md' 'desktop/skills/*' | grep -vxF "$REF")"
else
  CMDS="$(find .claude/commands -name '*.md' | sort)"; DOCS="$(find .claude/make-it/confluence-docs desktop/skills -name '*.md' 2>/dev/null | sort)"
  MORE="$(find .claude/make-it/references .claude/make-it/sdd desktop/skills -type f 2>/dev/null | grep -vxF "$REF" | sort)"
fi

flat() { tr '\n' ' ' | tr -s ' '; }
# has FILE SENTENCE: the flattened file holds the whole sentence
has() { flat < "$1" | gq -F -- "$2" || { echo "  missing in $1: $2"; false; }; }
# row FILE LINE: the file holds exactly this line, once
row() { [ "$(grep -cxF -- "$2" "$1")" = 1 ] || { echo "  not exactly once in $1: $2"; false; }; }
# none REGEX FILE...: no flattened file matches (case ignored)
none() { local re="$1" f m=0; shift; for f in "$@"; do if flat < "$f" | gq -iE -- "$re"; then echo "  in $f: /$re/"; m=1; fi; done; [ "$m" = 0 ]; }
# units FILE: one unit per line (a sentence, list item, table cell or code line), whitespace flattened
units() {
  awk '/^[[:space:]]*```/{c = !c} c || /^[[:space:]]*([-*+] |[0-9]+[.] |#|```|$)/{print "<BR>"} {print}' "$1" | flat |
    perl -pe 's/<BR>|\|/\n/g; s/([.!?]["\x27)]?) (?=\S)/$1\n/g' | sed -E 's/^ +//; s/ +$//' | awk 'NF'
}

# 1. the rule, sentence by sentence
RULE=(
  'Using a specialist and recording one are two separate jobs.'
  'Each project has one project specialist, recorded in the `expert_persona` field of `app-context.json`.'
  'It is a fact about the project, like its stack: recorded once, and updated only when its scope changes (below).'
  'Only three skills write `expert_persona`: `/make-it` records it at Design, `/retrofit-it` records it when it builds `app-context.json` from an existing app, and `/resume-it` re-checks it when new work changes the project'"'"'s scope.'
  'No other skill writes it.'
  'No skill overwrites the project specialist without saying so.'
  'Every writer that replaces an existing record with a different one says so the same way: one plain line to the user and the same line in `CHANGELOG.md`; it asks nothing.'
  'A re-check that gives the same specialists and signals writes nothing.'
  'The project'"'"'s scope changes when its signals change: a signal added, a signal removed, or an unconfirmed signal confirmed or disproved.'
  'The writer then works the record out again by the same rule, so it can go up or down, never below the floor.'
  'On every change it rewrites `set_by` and `set_at`, and the `CHANGELOG.md` line is the history.'
  'Every skill that changes or judges code reads the project specialist, then adds the specialist its own task needs, the way `/resolve-it` does.'
  'For a run, the task specialist leads the work and is held to the project specialist'"'"'s checks and output standard as well: that is what working as both means.'
  'A run never changes the record.'
  'With no record, a skill works as its task specialist alone and says nothing.'
  '`/dispatch-it` and `/subagent-it` adopt no specialist themselves; every agent they launch on app code is handed the project specialist plus the one its task needs.'
  'Skills that do not work on an app'"'"'s code get no project specialist.'
  'Every project records a named specialist: "generalist" is not a value and not a rule.'
  'The floor specialist is always in the record: primary when nothing outranks it, otherwise in `added` (rule 2 below).'
  'Nothing lowers a project below its floor.'
  'A writer sets `project_type` before it records `expert_persona`.'
  'With an empty or unknown `project_type` there is no floor, and no other type'"'"'s floor is assumed (not the web-app one either): the writer records nothing until the type is set.'
  '`expert_persona` holds a record, not a text value: the primary specialist, any added ones (security, reliability, data, ...), the signals that led to each, and which skill set it and when.'
  'A signal the code or the answers could not confirm is marked `"unconfirmed": true`.'
  'A plain text value that names a specialist (an app recorded before this shape) is read as the primary specialist, with no added specialists and no recorded signals.'
  'A text value that names no specialist ("generalist", "none" or empty), a record whose `primary.specialist` is empty, and no field at all are each read as no record.'
  'A reader never rewrites any of them; `/resume-it` brings the app up to this shape.'
  'Which specialist is the project'"'"'s primary is decided by the order in rule 2, not by this table.'
  '**Signals set the project specialist.** Only the three writers apply these, when they record or re-check `expert_persona`; every other skill reads the record instead.'
  '1. Security: payments, personal data (PII) or health data (PHI) in `compliance`, `purpose` or `features` → **Application security engineer**.'
  '2. Data: `multi_tenancy.needed == true`, or the answers describe data at scale → **Data engineer / DBA** (isolation, indexing, partitioning, safe migration and rollback).'
  '3. Reliability / platform: `users.internal_or_external == "external"`, `users.estimated_count` in the thousands or more, or an uptime promise (an SLA) for production that the user named → **SRE** (SLOs, failure modes, rollback, alerts).'
  '`deployment.target` holds the cloud provider, not that promise, so the promise is read from the answers.'
  '4. AI: `ai_features.usage_level == "heavy"`, or `ai_features.who_edits_prompts` is not `developers` → **AI / prompt engineer** (evals, prompt drift, red-team set).'
  '5. The floor for the `project_type`.'
  '**The order decides the primary.** The highest specialist in this order that applies is primary; every other one that applies is added, in this order; the floor specialist is always in the record: primary when nothing outranks it, otherwise in `added`.'
  'A fixed order does not weigh how strong each signal is; that is accepted.'
  '**Never below the floor.** With no signal firing, the project specialist is the floor for its `project_type` (above). There is no generalist fallback.'
  '**Record once, read every run.** The three writers record the primary, the added ones and their signals in `expert_persona`; every other skill reads it and never works it out again or rewrites it.'
  'Adds its task specialist (rule 1) and works as both, as "Who reads it" says.'
  'Writes nothing to `expert_persona` unless it is `/make-it`, `/retrofit-it` or `/resume-it`, and then only as the rule above says.'
  'This is **not** a staffing recommendation (it never suggests hiring a human).'
  'Selection is **automatic and silent**: no user question.'
  'The only thing a skill says about it is the one line a writer says when it replaces a record.'
  'Imported by `make-it`, `retrofit-it`, `debug-it`, `nemo-it`, `fix-it`, `argo-it`, `resolve-it`, `dispatch-it` and `subagent-it`.'
)
for s in "${RULE[@]}"; do check "the reference says: ${s:0:90}" 'has "$REF" "$s"'; done
check "the import list names exactly the command files that import the reference" \
  '( want="$(for f in $CMDS; do gq -F "references/expert-personas.md" "$f" && basename "$f" .md; done | sort | tr "\n" " ")";
     got="$(flat < "$REF" | perl -ne "print \$1 if /Imported by (.*?)\./" | grep -oE "\`[a-z-]+\`" | tr -d "\`" | sort | tr "\n" " ")";
     [ "$want" = "$got" ] || { echo "  imports: $want / named: $got"; exit 1; } )'

# 2. the floor, row by row (project_type values as the template defines them), and no sixth row
FLOOR=(
  '| `web-app` | Senior full-stack engineer of its stack |'
  '| `api-service` | Senior backend engineer of its stack |'
  '| `cli` | Senior tooling engineer of its language |'
  '| `library` | Senior library maintainer (public API and compatibility) |'
  '| `extension` | Senior extension engineer for its host (the editor or the browser) |'
)
for r in "${FLOOR[@]}"; do check "floor row: $r" 'row "$REF" "$r"'; done
# floorrows FILE: the number of body rows in the floor table
floorrows() { awk '/^[|] `project_type` [|] Floor specialist [|]/ {t = 1; next} t && /^[|]---/ {next} t && /^[|]/ {n++; next} t {t = 0} END {print n + 0}' "$1"; }
check "the floor table has exactly those five rows" '[ "$(floorrows "$REF")" = 5 ] || { echo "  floor rows: $(floorrows "$REF")"; false; }'
check "every floor value is a project_type the template defines" \
  '( for t in web-app api-service cli library extension; do gq -F "| \`$t\` |" "$TPL" || { echo "  template has no project_type $t"; exit 1; }; done )'

# 3. the template: who writes it, and its shape
TROW='| expert_persona | /make-it (Design), /retrofit-it, /resume-it (on a scope change) | The project specialist record (see `references/expert-personas.md`): `primary` and `added` specialists, each with the `signals` that led to it (a signal can be `"unconfirmed": true`), and `set_by` / `set_at`. No other skill writes it. An older plain text value that names a specialist is read as the primary; a text value naming none ("generalist", "none" or empty) or a record with an empty `primary.specialist` means no record. |'
check "the template's field row names the three writers, the record, and what reads as no record" 'row "$TPL" "$TROW"'
# shape FILE HEADING: the first ```json block after HEADING (or the file's first, with no heading) parses, and its
# expert_persona is the record; with "example" set, it is filled in and holds an unconfirmed signal. No specialist is
# a generalist, and the file holds the key "expert_persona": once, never with a text value.
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
check "the template's JSON holds expert_persona once, as the record: primary, added, set_by, set_at" 'shape "$TPL" ""'
check "the reference's worked example is that record, filled in, set by a writer, floor included, an unconfirmed signal" 'shape "$REF" "## The record" example'

# 4. none of the old rule is back, and the targeted bans hold
OLD='cached (default )?hint|re-infer(s|red)? (per|each|every) run|skills re-infer|cache, don.t trust|stays? (a )?(fast |competent )?generalist|generalist is the right|do \*?not\*? force a persona'
check "no reference, template, command or user doc keeps the old wording (cached hint, re-infer each run, stay generalist)" \
  'none "$OLD" "$REF" "$TPL" $CMDS $DOCS'
check "no file names \"any skill\" as a writer of the field" \
  'none "expert_persona \| [^|]*any skill|any skill (may |can )?(write|record|set|update)s?" "$REF" "$TPL" $CMDS'
BANS='re-infer|recomput|general-purpose|\b(record|records|recorded|use|uses|get|gets) no specialist|\bquietly\b|\bapprov|highest-risk|higher-risk|raise to primary|^\| `make-it` (build|/ retrofit)'
check "the reference has none of: re-infer, recompute, general-purpose, \"no specialist\" as a value, quietly, approval, highest-risk" \
  'none "$BANS" "$REF" && ! gq -E "^\| \`make-it\` (build|/ retrofit)" "$REF"'
check "neither the reference nor the template holds \"expert_persona\": with a text value" \
  'none "\"expert_persona\": *\"" "$REF" "$TPL"'

# 5. no other file writes the field. The <expert_persona> tag is dropped first: it is a block, not the field.
# Provenance that names one of the three writers ("set by /make-it") is dropped before the verbs are matched.
WRITE='\b(record|records|recording|write|writes|writing|written|store|stores|storing|stored|cache|caches|caching|save|saves|saving|saved|update|updates|updating|updated|overwrite|overwrites|overwriting|populate|populates|fill in|fills in|set|sets|setting|change|changes|changing|changed|migrate|migrates|put|puts|putting|replace|replaces|replacing|replaced|assign|assigns|assigned|edit|edits|editing|edited)\b'
PROV='\b(set|recorded|written|updated|re-checked) by `?/?(make-it|retrofit-it|resume-it)\b'
writers() {
  local f
  for f in $CMDS $MORE; do
    case "$f" in */commands/make-it.md|*/commands/retrofit-it.md|*/commands/resume-it.md) continue ;; esac
    units "$f" | perl -ne 's{</?expert_persona>}{}g; s{'"$PROV"'}{}gi; print "'"$f"': $_" if /expert_persona/ && /'"$WRITE"'/i'
    grep -nE '^[[:space:]]*[{,]?[[:space:]]*"expert_persona"[[:space:]]*:' "$f" | sed "s|^|$f: json line |" || true
  done
}
W="$(writers)"
check "no file but make-it.md, retrofit-it.md and resume-it.md tells the AI to write expert_persona (commands, references, SDD prompts, desktop skills)" \
  '[ -z "$W" ] || { printf "%s\n" "$W" | cut -c1-220 | sed "s/^/  writes the field: /"; false; }'

# 6. controls (this repo only): each opposite fails, and a tag or real-writer provenance passes
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$REF" "$TPL" $CMDS $DOCS $MORE | tar -xf - -C "$d"; echo "$d"; }
  # opp FILE PERL: the copy with one edit must fail this script
  opp() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  # same FILE PERL: the copy with one edit must still pass
  same() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && bash "$SELF" "$d" >/dev/null 2>&1; }
  # swap FILE OLD NEW: OLD (whitespace-tolerant, literal) replaced by NEW must fail; add FILE AFTER TEXT: TEXT after AFTER
  swap() { local d; d="$(copy)"; O="$2" N="$3" perl -0pi -e 'my $o = quotemeta($ENV{O}); $o =~ s/\\ /\\s+/g; s/$o/$ENV{N}/' "$d/$1"
           ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  add() { swap "$1" "$2" "$2$3"; }
  DBG=.claude/commands/debug-it.md
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  # the old rule
  check "(control) fails with the cached hint back" \
    'add "$REF" "Selection is **automatic and silent**: no user question." " The optional \`expert_persona\` field in app-context is only a cached default hint; skills re-infer per run because signals change."'
  check "(control) fails with \"stay generalist\" back as rule 3" \
    'opp "$REF" "s/\*\*Never below the floor\.\*\*[^\n]*(\n   [^\n]*)*/**Below all thresholds → stay generalist.** If nothing risky fires, do *not* force a persona./"'
  check "(control) fails when \"any skill\" writes it (the template row)" \
    'opp "$TPL" "s/\| expert_persona \| [^|]* \|/| expert_persona | Design \/ any skill |/"'
  # the 15 reversals from the S1 review, each one
  check "(control) R1 fails: a skill may re-infer the project specialist" \
    'add "$REF" "No other skill writes it." " A skill may re-infer the project specialist from the signals whenever they look different."'
  check "(control) R2 fails: other skills recompute it each run" \
    'add "$REF" "No other skill writes it." " Other skills recompute it from the signals on each run and use their result instead."'
  check "(control) R3 fails: /make-it and /retrofit-it may replace it quietly" \
    'add "$REF" "No skill overwrites the project specialist without saying so." " Except: /make-it and /retrofit-it may replace it quietly."'
  check "(control) R4 fails: /resume-it asks the user to approve" \
    'add "$REF" "it asks nothing." " Before changing it, /resume-it asks the user to approve."'
  check "(control) R5 fails: a low-risk prototype may use a general-purpose engineer" \
    'add "$REF" "Nothing lowers a project below its floor." " A low-risk prototype may use a general-purpose engineer instead."'
  check "(control) R6 fails: an extra floor row for a prototype with no specialist" \
    'opp "$REF" "s/^(\| \`extension\` \|[^\n]*\n)/\$1| \`prototype\` | No specialist (general-purpose) |\n/m"'
  check "(control) R6b fails: an extra floor row worded with none of the banned words" \
    'opp "$REF" "s/^(\| \`extension\` \|[^\n]*\n)/\$1| \`prototype\` | Whoever is free |\n/m"'
  check "(control) R7 fails: a throwaway script records no specialist" \
    'add "$REF" "Nothing lowers a project below its floor." " For a throwaway script, record no specialist."'
  check "(control) R8 fails: the worked example's primary is Generalist" \
    'opp "$REF" "s/\"specialist\": \"Application security engineer\"/\"specialist\": \"Generalist\"/"'
  check "(control) R9a fails: security moved below data in the order" \
    'swap "$REF" "1. Security: payments" "1. Data first, then security: payments"'
  check "(control) R9b fails: the order sentence reversed (the floor is always primary)" \
    'swap "$REF" "The highest specialist in this order that applies is primary;" "The floor is always primary;"'
  check "(control) R10 fails: debug-it puts the persona into expert_persona" \
    'add "$DBG" "</expert_persona>" "\n\nPut the persona you chose into \`expert_persona\` in app-context.json."'
  check "(control) R11 fails: debug-it replaces expert_persona" \
    'add "$DBG" "</expert_persona>" "\n\nReplace \`expert_persona\` with the persona you chose."'
  check "(control) R12 fails: debug-it, passive: expert_persona is then updated" \
    'add "$DBG" "</expert_persona>" "\n\nThe \`expert_persona\` field in app-context.json is then updated to the persona you chose."'
  check "(control) R13 fails: \"is set by /debug-it\" (provenance naming a non-writer)" \
    'add "$DBG" "</expert_persona>" "\n\nThe \`expert_persona\` field is set by /debug-it."'
  check "(control) R14 fails: debug-it carries a JSON block holding \"expert_persona\":" \
    'add "$DBG" "</expert_persona>" "\n\nThen look at app-context.json:\n\n\`\`\`json\n\"expert_persona\": { \"primary\": { \"specialist\": \"SRE\", \"signals\": [] } }\n\`\`\`\n"'
  check "(control) R15a fails: a second \"expert_persona\": \"generalist\" key in the template" \
    'opp "$TPL" "s/(\n  \"skipped_guardrails\": \{\})/\n  \"expert_persona\": \"generalist\",\$1/"'
  check "(control) R15b fails: an extra JSON example in the template with the old text value" \
    'opp "$TPL" "s/\z/\n\`\`\`json\n{ \"expert_persona\": \"Application security engineer\" }\n\`\`\`\n/"'
  # the wider scan
  check "(control) fails with a write of the field in a reference file (parallel-dispatch.md)" \
    'opp .claude/make-it/references/parallel-dispatch.md "s/\A/Store the chosen persona in \`expert_persona\`.\n\n/"'
  check "(control) fails with a write of the field in an SDD prompt template (implementer-prompt.md)" \
    'opp .claude/make-it/sdd/implementer-prompt.md "s/\z/\nWhen done, update \`expert_persona\` with your specialist.\n/"'
  check "(control) fails with a write of the field in a Desktop skill (guardrails/SKILL.md)" \
    'opp desktop/skills/guardrails/SKILL.md "s/\z/\nRecord the persona in \`expert_persona\`.\n/"'
  check "(control) passes with provenance naming a real writer (\"set by /make-it\") in try-it.md" \
    'same .claude/commands/try-it.md "s/\A/The \`expert_persona\` field is set by \`\/make-it\` at Design.\n\n/"'
  check "(control) passes with an <expert_persona> tag block whose sentence has a write verb (try-it.md): a tag is not the field" \
    'same .claude/commands/try-it.md "s/\A/<expert_persona>\nWrite each check as a QA engineer would.\n<\/expert_persona>\n\n/"'
  # each new rule sentence has its opposite
  check "(control) F6 fails: a writer may replace a record without a word" \
    'swap "$REF" "says so the same way: one plain line to the user and the same line in \`CHANGELOG.md\`; it asks nothing." "may replace it without a word."'
  check "(control) F6 fails: a re-check always rewrites the record" \
    'swap "$REF" "A re-check that gives the same specialists and signals writes nothing." "A re-check always rewrites the record."'
  check "(control) F5 fails: scope changes when the user says so" \
    'swap "$REF" "The project'\''s scope changes when its signals change:" "The project'\''s scope changes when the user says so:"'
  check "(control) F5 fails: the record can only go up" \
    'swap "$REF" "so it can go up or down, never below the floor." "so it can only go up."'
  check "(control) F5 fails: set_by and set_at are kept on a change" \
    'swap "$REF" "On every change it rewrites \`set_by\` and \`set_at\`," "On every change it keeps \`set_by\` and \`set_at\`,"'
  check "(control) F1 fails: the task specialist replaces the project specialist for a run" \
    'swap "$REF" "the task specialist leads the work and is held to the project specialist'\''s checks and output standard as well" "the task specialist replaces the project specialist"'
  check "(control) F1 fails: a run may change the record" 'swap "$REF" "A run never changes the record." "A run may change the record."'
  check "(control) F7 fails: skills off app code get none (no fixed specialist either)" \
    'swap "$REF" "code get no project specialist." "code get none."'
  check "(control) F4 fails: the floor is dropped when something outranks it" \
    'swap "$REF" "The floor specialist is always in the record: primary when nothing outranks it, otherwise in \`added\` (rule 2 below)." "The floor specialist is dropped when something outranks it."'
  check "(control) fails with \"nothing lowers a project below its floor\" dropped" \
    'swap "$REF" "Nothing lowers a project below its floor." ""'
  check "(control) F10 fails: an unknown project_type gets the web-app floor" \
    'swap "$REF" "there is no floor, and no other type'\''s floor is assumed (not the web-app one either): the writer records nothing until the type is set." "use the web-app floor."'
  check "(control) F10 fails: project_type need not be set first" \
    'swap "$REF" "A writer sets \`project_type\` before it records \`expert_persona\`." ""'
  check "(control) F8 fails: \"generalist\" text is read as the primary" \
    'swap "$REF" "A text value that names no specialist (\"generalist\", \"none\" or empty), a record" "A record"'
  check "(control) F8 fails: a reader may rewrite an older value" \
    'swap "$REF" "A reader never rewrites any of them;" "A reader may rewrite them;"'
  check "(control) F1 fails: the catalogue picks the primary again" \
    'swap "$REF" "Which specialist is the project'\''s primary is decided by the order in rule 2, not by this table." "When several apply, adopt the most important persona as primary."'
  check "(control) F3 fails: every skill applies the signals" \
    'swap "$REF" "Only the three writers apply these, when they record or re-check \`expert_persona\`; every other skill reads the record instead." "Every skill reads these fields and layers personas in."'
  check "(control) F3 fails: a data row is back in the catalogue" \
    'opp "$REF" "s/^(\| \`retrofit-it\` \(legacy)/| \`make-it\` \/ retrofit — data at scale or multi-tenant | Data engineer \/ DBA | a | b | c |\n\$1/m"'
  check "(control) D1 fails: the floor is left out of the record when outranked" \
    'swap "$REF" "the floor specialist is always in the record: primary when nothing outranks it, otherwise in \`added\`." "the floor is left out."'
  check "(control) D1 fails: the accepted catch is dropped" \
    'swap "$REF" "A fixed order does not weigh how strong each signal is; that is accepted." ""'
  check "(control) F10 fails: the SLA is read from deployment.target again" \
    'swap "$REF" "\`deployment.target\` holds the cloud provider, not that promise, so the promise is read from the answers." "\`deployment.target\` = production with SLA."'
  check "(control) fails with rule 4 dropping \"never works it out again\"" \
    'swap "$REF" "never works it out again or rewrites it." "works it out again when it likes."'
  check "(control) fails with the invoke step not working as both" \
    'swap "$REF" "Adds its task specialist (rule 1) and works as both, as \"Who reads it\" says." "Adds its task specialist (rule 1)."'
  check "(control) F10 fails: the silent clarifier is dropped" \
    'swap "$REF" "The only thing a skill says about it is the one line a writer says when it replaces a record." ""'
  check "(control) F10 fails: the import list leaves out resolve-it" \
    'swap "$REF" "\`argo-it\`, \`resolve-it\`, \`dispatch-it\`" "\`argo-it\`, \`dispatch-it\`"'
  check "(control) F10 fails: the extension floor says \"for that editor\" again" \
    'swap "$REF" "for its host (the editor or the browser)" "for that editor"'
  check "(control) F8 fails: the template row reads an empty record as a value" \
    'swap "$TPL" "; a text value naming none (\"generalist\", \"none\" or empty) or a record with an empty \`primary.specialist\` means no record." "; an empty one means no record."'
  check "(control) fails with a floor row dropped (cli)" 'opp "$REF" "s/^\| \`cli\` \|[^\n]*\n//m"'
  check "(control) fails with the template's field back to plain text" \
    'opp "$TPL" "s/\"expert_persona\": \{.*?\n  \},/\"expert_persona\": \"\",/s"'
  check "(control) fails with set_by dropped from the template's record" 'opp "$TPL" "s/\n *\"set_by\": \"\",//"'
  check "(control) fails with the example's unconfirmed signal confirmed" \
    'opp "$REF" "s/\"unconfirmed\": true/\"unconfirmed\": false/g"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
