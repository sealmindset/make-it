#!/usr/bin/env bash
# E11-S1 (the owner's rule, 2026-11-21): one project specialist, recorded by the skills that define the project.
# Contract these checks pin (references/expert-personas.md and templates/app-context.md, as the agent reads them):
#   - Using a specialist and recording one are two separate jobs. One project specialist, a fact about the project
#     recorded in app-context.json's expert_persona, written only by /make-it (Design), /retrofit-it and /resume-it
#     (on a scope change). No skill overwrites it without saying so; /resume-it says so in one line to the user and in
#     CHANGELOG.md, with no ask. Every skill that changes or judges code reads it and adds its task specialist; the
#     coordinators adopt none and hand both to their agents; skills off app code get none. Silent; not staffing advice.
#   - Always a named specialist: the floor per project_type, row by row. No generalist value and no generalist rule.
#   - The record's shape (primary, added, each with signals that can be unconfirmed, set_by, set_at), in the template's
#     JSON and in the reference's worked example; an old text value or an empty one is still read.
#   - None of the old wording is back: the "cached default hint", "re-infer each run", "stay generalist", "any skill"
#     as a writer.
#   - No command file but make-it.md, retrofit-it.md and resume-it.md tells the AI to write the field. The XML-style
#     <expert_persona> block several skills carry is a tag, not the field, and is not counted.
# A tripwire, not a proof, and no rule is added per bypass. It cannot catch: a write said with a verb not in WRITE (or
# a passive "set by" / "recorded by" in another skill, which reads as provenance and is allowed); a write split across
# two sentences; a write in a file that is not a command file; whether a skill really does what the reference says.
# Usage: test-project-specialist-rule.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# their opposites (and pass on a tag that is not a write).
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
OV=.claude/make-it/confluence-docs/00-make-it-framework-overview.md
if [ -z "${1:-}" ]; then
  CMDS="$(git ls-files '.claude/commands/*.md')"; DOCS="$(git ls-files '.claude/make-it/confluence-docs/*.md' 'desktop/skills/*.md')"
else
  CMDS="$(find .claude/commands -name '*.md' | sort)"; DOCS="$(find .claude/make-it/confluence-docs desktop/skills -name '*.md' 2>/dev/null | sort)"
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
  'It is a fact about the project, like its stack: recorded once, and updated only when the project changes.'
  'Only three skills write `expert_persona`: `/make-it` records it at Design, `/retrofit-it` records it when it builds `app-context.json` from an existing app, and `/resume-it` re-checks it when new work changes the project'"'"'s scope.'
  'No other skill writes it.'
  'No skill overwrites the project specialist without saying so.'
  'When `/resume-it` changes it, it says so in one plain line to the user and writes the same line in `CHANGELOG.md`; it asks nothing.'
  'Every skill that changes or judges code reads the project specialist, then adds the specialist its own task needs, the way `/resolve-it` does.'
  'With no record, a skill works as its task specialist alone and says nothing.'
  '`/dispatch-it` and `/subagent-it` adopt no specialist themselves; every agent they launch on app code is handed the project specialist plus the one its task needs.'
  'Skills that do not work on an app'"'"'s code get none.'
  'Every project records a named specialist: "generalist" is not a value and not a rule.'
  'The signals in the auto-inference rules raise the floor or add to it; nothing lowers a project below its floor.'
  '`expert_persona` holds a record, not a text value: the primary specialist, any added ones (security, reliability, data, ...), the signals that led to each, and which skill set it and when.'
  'A signal the code or the answers could not confirm is marked `"unconfirmed": true`.'
  'A plain text value (an app recorded before this shape) is read as the primary specialist, with no added specialists and no recorded signals.'
  'An empty value, or no field, is read as no record.'
  'A reader never rewrites either one; `/resume-it` brings the app up to this shape.'
  '**Never below the floor.** With no signal firing, the project specialist is the floor for its `project_type` (above). There is no generalist fallback.'
  '**Record once, read every run.** The three writers record the primary, the added ones and their signals in `expert_persona`; every other skill reads it and never re-infers or rewrites it.'
  'Writes nothing to `expert_persona` unless it is `/make-it`, `/retrofit-it` or `/resume-it`, and then only as the rule above says.'
  'This is **not** a staffing recommendation (it never suggests hiring a human).'
  'Selection is **automatic and silent**: no user question.'
)
for s in "${RULE[@]}"; do check "the reference says: ${s:0:90}" 'has "$REF" "$s"'; done

# 2. the floor, row by row (project_type values as the template defines them)
FLOOR=(
  '| `web-app` | Senior full-stack engineer of its stack |'
  '| `api-service` | Senior backend engineer of its stack |'
  '| `cli` | Senior tooling engineer of its language |'
  '| `library` | Senior library maintainer (public API and compatibility) |'
  '| `extension` | Senior extension engineer for that editor |'
)
for r in "${FLOOR[@]}"; do check "floor row: $r" 'row "$REF" "$r"'; done
check "every floor value is a project_type the template defines" \
  '( for t in web-app api-service cli library extension; do gq -F "| \`$t\` |" "$TPL" || { echo "  template has no project_type $t"; exit 1; }; done )'

# 3. the template: who writes it, and its shape
TROW='| expert_persona | /make-it (Design), /retrofit-it, /resume-it (on a scope change) | The project specialist record (see `references/expert-personas.md`): `primary` and `added` specialists, each with the `signals` that led to it (a signal can be `"unconfirmed": true`), and `set_by` / `set_at`. No other skill writes it. An older plain text value is read as the primary; an empty one means no record. |'
check "the template's field row names the three writers and the record" 'row "$TPL" "$TROW"'
# shape FILE HEADING: the first ```json block after HEADING (or the file's first, with no heading) parses, and its
# expert_persona is the record; with "example" set, it is filled in and holds an unconfirmed signal
shape() {
  python3 -I - "$1" "$2" "${3:-}" <<'PY'
import json, re, sys
path, head, example = sys.argv[1], sys.argv[2], sys.argv[3] == "example"
def fail(msg): print(f"  {path}: {msg}"); sys.exit(1)  # stdout: stderr is kept for real errors
t = open(path, encoding="utf-8").read()
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
    for g in s["signals"]:
        if not isinstance(g, dict) or set(g) != {"signal", "unconfirmed"} or not isinstance(g["unconfirmed"], bool):
            fail(f"a signal entry is {g!r}")
if example:
    if not all(s["specialist"] and s["signals"] for s in specs) or not ep["added"]: fail("the example is not filled in")
    if ep["set_by"] not in ("/make-it", "/retrofit-it", "/resume-it") or not ep["set_at"]: fail("set_by/set_at")
    if not any(g["unconfirmed"] for s in specs for g in s["signals"]): fail("no signal is marked unconfirmed")
PY
}
check "the template's JSON holds expert_persona as the record: primary, added, set_by, set_at" 'shape "$TPL" ""'
check "the reference's worked example is that record, filled in, set by a writer, with an unconfirmed signal" 'shape "$REF" "## The record" example'

# 4. none of the old rule is back
OLD='cached (default )?hint|re-infer(s|red)? (per|each|every) run|skills re-infer|cache, don.t trust|stays? (a )?(fast |competent )?generalist|generalist is the right|do \*?not\*? force a persona'
check "no reference, template, command or user doc keeps the old wording (cached hint, re-infer each run, stay generalist)" \
  'none "$OLD" "$REF" "$TPL" $CMDS $DOCS'
check "no file names \"any skill\" as a writer of the field" \
  'none "expert_persona \| [^|]*any skill|any skill (may |can )?(write|record|set|update)s?" "$REF" "$TPL" $CMDS'

# 5. no other command file writes the field. The <expert_persona> tag is dropped first: it is a block, not the field.
WRITE='\b(record|records|recording|write|writes|writing|store|stores|storing|cache|caches|caching|save|saves|saving|update|updates|updating|overwrite|overwrites|overwriting|populate|populates|fill in|fills in|setting|change|changes|changing|migrate|migrates)\b|\bsets?\b(?! by)'
writers() {
  local f
  for f in $CMDS; do
    case "$(basename "$f")" in make-it.md|retrofit-it.md|resume-it.md) continue ;; esac
    units "$f" | perl -ne 's{</?expert_persona>}{}g; print "'"$f"': $_" if /expert_persona/ && /'"$WRITE"'/i'
  done
}
W="$(writers)"
check "no command file but make-it.md, retrofit-it.md and resume-it.md tells the AI to write expert_persona" \
  '[ -z "$W" ] || { printf "%s\n" "$W" | cut -c1-220 | sed "s/^/  writes the field: /"; false; }'

# 6. controls (this repo only): each opposite fails, and a tag that is not a write passes
if [ -z "${1:-}" ]; then
  copy() { local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"; tar -cf - "$REF" "$TPL" $CMDS $DOCS | tar -xf - -C "$d"; echo "$d"; }
  # opp FILE PERL: the copy with one edit must fail this script
  opp() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1; }
  # same FILE PERL: the copy with one edit must still pass
  same() { local d; d="$(copy)"; perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && bash "$SELF" "$d" >/dev/null 2>&1; }
  check "(control) the unchanged copy passes" 'd="$(copy)"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with the cached hint back" \
    'opp "$REF" "s/(Selection is \*\*automatic and silent\*\*: no user question\.)/\$1 The optional \`expert_persona\` field in app-context is only a cached default hint; skills re-infer per run because signals change./"'
  check "(control) fails with \"re-infer each run\" back in rule 4" \
    'opp "$REF" "s/every other skill reads it and never re-infers or rewrites it\./every skill may re-infer it each run because scale can change./"'
  check "(control) fails with \"stay generalist\" back as rule 3" \
    'opp "$REF" "s/\*\*Never below the floor\.\*\*[^\n]*(\n   [^\n]*)*/**Below all thresholds → stay generalist.** If nothing risky fires, do *not* force a persona./"'
  check "(control) fails when \"any skill\" writes it (the template row)" \
    'opp "$TPL" "s/\| expert_persona \| [^|]* \|/| expert_persona | Design \/ any skill |/"'
  check "(control) fails with \"without saying so\" dropped" \
    'opp "$REF" "s/No skill overwrites the project specialist without saying so\./A skill may overwrite the project specialist./"'
  check "(control) fails with a floor row dropped (cli)" 'opp "$REF" "s/^\| \`cli\` \|[^\n]*\n//m"'
  check "(control) fails with a floor row weakened to a generalist (library)" \
    'opp "$REF" "s/^\| \`library\` \| [^\n]*/| \`library\` | Generalist |/m"'
  check "(control) fails with a write of the field in another command file (debug-it.md)" \
    'opp .claude/commands/debug-it.md "s/^(<\/expert_persona>\n)/\$1\nRecord the persona you chose in \`expert_persona\` in app-context.json.\n/m"'
  check "(control) fails with a wrapped \"set\" write of the field in another command file (nemo-it.md)" \
    'opp .claude/commands/nemo-it.md "s/^(\*\*Scan modes\*\*)/Then set\n\`expert_persona\` to the application security engineer.\n\n\$1/m"'
  check "(control) passes with an <expert_persona> tag block whose sentence has a write verb (try-it.md): a tag is not the field" \
    'same .claude/commands/try-it.md "s/\A/<expert_persona>\nWrite each check as a QA engineer would.\n<\/expert_persona>\n\n/"'
  check "(control) fails with the template's field back to plain text" \
    'opp "$TPL" "s/\"expert_persona\": \{.*?\n  \},/\"expert_persona\": \"\",/s"'
  check "(control) fails with set_by dropped from the template's record" 'opp "$TPL" "s/\n *\"set_by\": \"\",//"'
  check "(control) fails with the example's unconfirmed signal confirmed" \
    'opp "$REF" "s/\"unconfirmed\": true/\"unconfirmed\": false/g"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
