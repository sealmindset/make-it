#!/usr/bin/env bash
# v1.45.0: AI accounting is defined once (ai-accounting.md + AC01-AC16 / ACV01-ACV03) and wired the same way everywhere.
# Contract these checks pin (the change must satisfy it):
#   - build-standards.md defines AC01-AC16 and ACV01-ACV03, each exactly once; nothing anywhere names an AC id outside them.
#   - Every "section N" that build-standards, Prompt #10g or the skills cite exists in ai-accounting.md.
#   - Every AI/BN/DI check id that ai-accounting.md cites is defined in build-standards.md.
#   - The 13 tables of section 3 are the 13 in #10g's migration line, and resume-it's ask says 13.
#   - make-it (9f, 33b), retrofit-it (F3, 12b, Step 5b, plan line, AI-accounting-only run), resume-it (catch-up,
#     suggestion row, ai-accounting-addition step) and guardrails carry the wiring; app-context.json's template parses.
#   - Each core check fails on a copy of the tree with one defect planted (the controls), so a pass means something.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# "grep -q" quits at its first match and SIGPIPEs the writer under pipefail; gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# The whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise).
ERRF="$(mktemp)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -f "$ERRF"; rm -rf "${TMPT:-}"' EXIT

REF=.claude/make-it/references
CMD=.claude/commands

# The core checks, as one checker run against a tree: prints one line per problem, exits 1 if any.
cat > "${TMPDIR:-/tmp}/ai-acct-check.$$.py" <<'PY'
import json, os, re, sys
root = sys.argv[1]
def rd(p): return open(os.path.join(root, p)).read()
REF = ".claude/make-it/references"; CMD = ".claude/commands"
spec, bs, pt = rd(f"{REF}/ai-accounting.md"), rd(f"{REF}/build-standards.md"), rd(f"{REF}/prompt-templates.md")
probs = []
# 1. ids defined once, none outside the range
want = [f"AC{n:02d}" for n in range(1, 17)] + [f"ACV{n:02d}" for n in range(1, 4)]
for i in want:
    c = len(re.findall(r"^\*\*" + i + r"\*\* \[", bs, re.M))
    if c != 1: probs.append(f"{i} defined {c} times in build-standards.md")
for d, _, fs in os.walk(os.path.join(root, ".claude")):
    for f in fs:
        if not f.endswith(".md"): continue
        for m in set(re.findall(r"\bACV?\d{2}\b", open(os.path.join(d, f)).read())):
            if m not in want: probs.append(f"{m} named in {f} but not defined")
# 2. cited sections exist in the spec
secs = set(re.findall(r"^## (\d+)\. ", spec, re.M))
acblock = bs[bs.index("## AI Accounting (when"):bs.index("## PWA / Mobile")]
p10g = pt[pt.index("### Prompt #10g"):pt.index("## Prompt #11")]
cited = re.findall(r"\bsections? (\d+)(?:-(\d+))?", acblock + p10g + rd(f"{CMD}/retrofit-it.md"))
for a, b in cited:
    for n in range(int(a), int(b or a) + 1):
        if str(n) not in secs: probs.append(f"section {n} cited but not in ai-accounting.md")
# 3. check ids the spec cites exist
for m in sorted(set(re.findall(r"\b(?:AI\d{2}[a-z]?|BN\d{2}|DI\d{2})\b", spec))):
    if not re.search(r"^\*\*" + m + r"\*\* \[", bs, re.M): probs.append(f"spec cites {m}, not defined in build-standards.md")
# 4. the table list agrees in three places
s3 = spec[spec.index("## 3. Data"):spec.index("## 4. ")]
tables = re.findall(r"^\*\*`([a-z_]+)`\*\*", s3, re.M)
mig = re.search(r"Migration: (.*?)\. tenant_id", p10g, re.S)
migt = re.findall(r"[a-z_]+", mig.group(1)) if mig else []
if sorted(tables) != sorted(migt): probs.append(f"section 3 tables {sorted(tables)} != #10g migration {sorted(migt)}")
if f"It's {len(tables)} new tables" not in re.sub(r"\s+", " ", rd(f"{CMD}/resume-it.md")):
    probs.append(f"resume-it's ask doesn't say {len(tables)} new tables")
# 5. the app-context template still parses, with the block
t = rd(".claude/make-it/templates/app-context.md")
try:
    j = json.loads(t[t.index("```json") + 7:t.index("```", t.index("```json") + 7)])
    if set(j.get("ai_accounting", {})) != {"enabled", "infra_source", "infra_tag_key", "ladder_verdict"}:
        probs.append("app-context ai_accounting block keys differ")
except Exception as e:
    probs.append(f"app-context JSON doesn't parse: {e}")
for p in probs: print(p)
sys.exit(1 if probs else 0)
PY
CHK="${TMPDIR:-/tmp}/ai-acct-check.$$.py"

# 1-5. the core checks on the real tree
out="$(python3 "$CHK" "$root" || true)"
check "core checks pass on this tree${out:+ ($out)}" '[ -z "$out" ]'

# Controls: each planted defect must make the checker fail.
TMPT="$(mktemp -d)"
plant() {  # plant NAME FILE PYTHON-REPLACE-EXPR
  rm -rf "$TMPT/t"; mkdir -p "$TMPT/t"; cp -R .claude "$TMPT/t/.claude"
  python3 - "$TMPT/t/$2" "$3" <<'PY'
# e is one of the fixed replace expressions written below in this script, never outside input.
import sys; p, e = sys.argv[1], sys.argv[2]; s = open(p).read(); n = eval(e, {"s": s})
assert n != s, "plant changed nothing"; open(p, "w").write(n)
PY
  check "control: $1 is caught" '! python3 "$CHK" "$TMPT/t" >/dev/null'
}
plant "a duplicate AC05" "$REF/build-standards.md" 's.replace("**AC06** [", "**AC05** [", 1)'
plant "an AC id outside the range" "$REF/guardrails.md" 's.replace("AC01-AC16, ACV01", "AC01-AC17, ACV01", 1)'
plant "a cited section that doesn't exist" "$REF/build-standards.md" 's.replace("(section 9)", "(section 19)", 1)'
plant "an unknown check id in the spec" "$REF/ai-accounting.md" 's.replace("(AI21)", "(AI99)", 1)'
plant "a table missing from #10g" "$REF/prompt-templates.md" 's.replace("vendor_spend, spend_statements", "spend_statements", 1)'
plant "a broken app-context template" ".claude/make-it/templates/app-context.md" 's.replace("\"ladder_verdict\": \"\"", "\"ladder_verdict\": ", 1)'

# 6. the wiring, skill by skill
check "make-it has build step 9f with #10g new-build" 'grep -F "9f. **AI Accounting**" $CMD/make-it.md | gq . && grep -F "Prompt #10g with MODE = new-build" $CMD/make-it.md | gq .'
check "make-it runs ACV01-ACV03 (33b) and lists AC01-AC16 in Part A" 'grep -F "33b. **Test AI accounting (ACV01-ACV03)**" $CMD/make-it.md | gq . && grep -F -- "- **AC01-AC16**: AI accounting" $CMD/make-it.md | gq .'
check "retrofit-it has Phase F3 with its user-facing name" 'grep -E "^\| Phase F3 \|.*Measuring what your AI costs and saves" $CMD/retrofit-it.md | gq .'
check "retrofit-it has 5a step 12b and 5b Step 5b" 'grep -F "12b. **AI Accounting (Prompt #10g, MODE = retrofit" $CMD/retrofit-it.md | gq . && grep -F "**Step 5b: \"Measuring what your AI costs and saves\"" $CMD/retrofit-it.md | gq .'
check "retrofit-it's phased plan names the step in 5b order" '[ "$(grep -nF "**Securing your AI features** --" $CMD/retrofit-it.md | cut -d: -f1)" -lt "$(grep -nF "**Measuring what your AI costs and saves** --" $CMD/retrofit-it.md | cut -d: -f1)" ]'
check "retrofit-it has the AI-accounting-only run" 'grep -F "**AI accounting only.** When" $CMD/retrofit-it.md | gq .'
check "retrofit-it verify lists AC01-AC16 and ACV01-ACV03" 'grep -F -- "- **AC01-AC16**: AI accounting" $CMD/retrofit-it.md | gq . && grep -F -- "- **ACV01-ACV03**: AI accounting" $CMD/retrofit-it.md | gq .'
check "resume-it catch-up scans AC01-AC16" 'grep -F "**AI Accounting (AC01-AC16):**" $CMD/resume-it.md | gq .'
check "resume-it offers it and has the addition step" 'grep -F "no AI accounting (AC01 GAP)" $CMD/resume-it.md | gq . && grep -F "<step name=\"ai-accounting-addition\">" $CMD/resume-it.md | gq .'
check "resume-it's ask is a pick, not a yes, and nothing is written before it" 'grep -F "A plain yes isn'"'"'t an answer -- ask which. '"'"'Not now'"'"': nothing was written" $CMD/resume-it.md | gq .'
check "only the build steps write the ladder report" '[ "$(grep -lF "to \`.make-it/ai-ladder.md\`" $CMD/*.md | tr "\n" " ")" = "$CMD/retrofit-it.md " ] && grep -F "Write the ladder report from step 1 to .make-it/ai-ladder.md." $REF/prompt-templates.md | gq .'
check "retrofit-it reads its argument" 'grep -F "<!-- User invoked: /retrofit-it \$ARGUMENTS -->" $CMD/retrofit-it.md | gq . && grep -F "\`\$ARGUMENTS\` is \`ai-accounting\`" $CMD/retrofit-it.md | gq .'
check "an app with no admin gate gets no statements either" 'grep -F "skip this step and STEP 5'"'"'s statements" $REF/prompt-templates.md | gq .'
check "guardrails carries the AI Accounting section" 'grep -F "### AI Accounting (MANDATORY for any app with AI features)" $REF/guardrails.md | gq .'
check "desktop make-it and guardrails ship the spec" 'grep -xF ".claude/make-it/references/ai-accounting.md" desktop/skills/make-it/refs.txt | gq . && grep -xF ".claude/make-it/references/ai-accounting.md" desktop/skills/guardrails/refs.txt | gq .'

# 7. nothing specific to the source app leaked into the spec or the skills
check "no source-app names in the spec" '! grep -niE "docai|vlf|keller|lawfirm|efilemn|attorney|law firm" $REF/ai-accounting.md | gq .'

check "no stderr from any check above" '[ ! -s "$ERRF" ]'
rm -f "$CHK"
[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || { echo "SOME CHECKS FAILED"; exit 1; }
