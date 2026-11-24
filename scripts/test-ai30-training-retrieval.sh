#!/usr/bin/env bash
# E02-S66 (the owner's calls, 2026-11-21): the governance document claimed OWASP's "AI04: Data Poisoning" was covered,
# citing prompt-management controls. Data and model poisoning is about training, fine-tuning and embedding or retrieval
# data, and make-it apps do none of those, so the row is "not applicable" -- and build-standards check AI30 enforces it.
# Contract these checks pin:
#   - AI30 exists once, after AI29, [Tier 0] [BLOCK] (every app, whatever ai_features.needed says), not [SECURITY FIX].
#   - What it detects, as two grep patterns written in AI30 itself: real sample lines go through them. Positives
#     (training libraries and loops, fine-tuning calls, embeddings calls, vector stores, in Python and JS/TS dependency
#     files and code) must hit; negatives (plain chat-completion code, ordinary dependencies) must not; both scaffolds
#     and the PWA overlay as shipped must have no hit.
#   - The accepted exception is the left-out record (left-out-record.md), in that file's own form, naming AI30; nothing
#     else makes one. A hit is never fixed on its own.
#   - AI30 says it is a tripwire that can be fooled both ways, and a boundary check, not protection against poisoning.
#   - The CI half is not built: any sentence that names CI, a pipeline or make-it-verify next to AI30 says "not built",
#     and no sentence there says AI30 protects against or prevents poisoning.
#   - The governance doc: the AI04 row says not applicable, enforced by check AI30; the AI08 row and the RAG gap row
#     name AI30; the checks table reads AI01-AI30, 34, and its total is the sum of its rows.
#   - Every AI range in make-it.md, resume-it.md, retrofit-it.md and the two docs reads AI01-AI30.
# A wording test is a tripwire, not a proof: it cannot see an agent skip the scan, and the patterns cannot see a library
# or call under another name. No build is run here.
# Usage: test-ai30-training-retrieval.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on
# planted opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# grep -q quits at its first match; under pipefail the writer's SIGPIPE flips the check. gq reads all of its input.
gq() { [ "$(grep -c "$@")" -gt 0 ]; }
# the whole run's stderr is caught; the last check fails on any of it (a bad regex reads as a pass otherwise)
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

BS=.claude/make-it/references/build-standards.md; LO=.claude/make-it/references/left-out-record.md
MK=.claude/commands/make-it.md; RS=.claude/commands/resume-it.md; RF=.claude/commands/retrofit-it.md
GV=docs/AI-GOVERNANCE-HOMEGROWN.md; DV=docs/DEVOPS-GUIDE.md
FILES="$BS $LO $MK $RS $RF $GV $DV"
flat() { tr '\n' ' ' | tr -s ' '; }
has() { printf "%s" "$1" | gq -F -- "$2" || { echo "  missing: $2" | cut -c1-200; false; }; }
row() { gq -xF -- "$2" "$1"; }

AI30="$(grep -E '^[*][*]AI30[*][*] ' "$BS" || true)"
# the two patterns, as AI30 writes them
DEP="$(printf "%s" "$AI30" | sed -nE "s/.*\`grep -nEi '([^']*)'\`.*/\1/p")"
CODE="$(printf "%s" "$AI30" | sed -nE "s/.*\`grep -nE '([^']*)'\`.*/\1/p")"
# hits FLAGS PATTERN LINE: how many times the pattern matches the line (0 or 1)
hits() { printf "%s\n" "$3" | grep -c "$1" -- "$2" || true; }

# 1. the check itself
check "AI30 exists once, is [Tier 0] [BLOCK], and is this check" \
  '[ "$(grep -cE "^[*][*]AI30[*][*] " "$BS")" = 1 ] && [ "$(grep -cE "^[*][*]AI30[*][*] \[Tier 0\] \[BLOCK\] [*][*]No model training, fine-tuning or retrieval unless it is an accepted exception[*][*] -- " "$BS")" = 1 ]'
check "AI30 is not a [SECURITY FIX] (that marker is for a hole open now)" '! printf "%s" "$AI30" | gq -F "[SECURITY FIX]"'
check "AI30 comes right after AI29 and is the last AI check (34 AI checks)" \
  '[ "$(grep -oE "^[*][*]AI[0-9]+[a-d]?[*][*]" "$BS" | tail -2 | tr "\n" " ")" = "**AI29** **AI30** " ] && [ "$(grep -cE "^[*][*]AI[0-9]+[a-d]?[*][*]" "$BS")" = 34 ]'
check "AI30 says why: make-it apps only send prompts and read replies, and poisoning is a risk of training, fine-tuning and retrieval" \
  'has "$AI30" "make-it apps send prompts to a model and read its replies. They do not train a model, fine-tune one, or add retrieval (embeddings or a vector store), and data and model poisoning (OWASP LLM04) is a risk of exactly those, so this check fails an app that adds one until the user accepts it."'
check "AI30 applies to every app, not only when ai_features.needed is set, and says why" \
  'has "$AI30" "It applies to every app, whatever \`ai_features.needed\` says: an app can add training or retrieval without that flag."'
check "AI30 names the files each scan reads and runs no model" \
  'has "$AI30" "Checked by reading files, with no model call. Take the files from \`git ls-files\` and fail on any line either scan finds: (1) dependencies -- in each \`requirements*.txt\`, \`pyproject.toml\`, \`package.json\`, \`Dockerfile*\`, \`docker-compose*.yml\` and \`compose*.yml\`, \`grep -nEi '"'"'" && has "$AI30" "(2) code -- in each \`*.py\`, \`*.ts\`, \`*.tsx\`, \`*.js\`, \`*.jsx\`, \`*.mjs\`, \`*.cjs\` and \`*.sql\` file, \`grep -nE '"'"'"'
check "AI30 names, in words, the four kinds it finds" \
  'has "$AI30" "Together they find training libraries and loops (torch, tensorflow, keras, scikit-learn, xgboost, transformers, peft, trl; \`.fit(\`, \`Trainer(\`, \`.backward()\`), fine-tuning API calls (\`fine_tuning\`, \`fineTuning\`), embeddings calls (\`embeddings.create(\`, \`embed_content(\`, \`embedMany(\`, \`Embeddings(\`) and vector stores (pgvector, chroma, pinecone, faiss, qdrant, weaviate, milvus, lancedb, llama-index; \`similarity_search\`, \`vector_store\`, \`CREATE EXTENSION vector\`)."'
check "a hit is never fixed on its own, nor removed as part of a group" \
  'has "$AI30" "A hit is never fixed on its own and never removed as part of a group of fixes: tell the user in plain words what was found and where (file and line), then the code comes out only at their word, or they leave AI30 out."'
check "the accepted exception is the left-out record, one line naming AI30, written by the skill that asked" \
  'has "$AI30" "**The accepted exception is the app'"'"'s left-out record** (\`~/.claude/make-it/references/left-out-record.md\`): one line under \`## Left out by your choice\` in \`.make-it-state.md\` whose checks name AI30, in that file'"'"'s form, written by the skill that asked, for example \`- model training or retrieval in the app -- checks AI30 -- left out 2026-11-21\`."'
check "the example line is in the record's own form, and the record still defines that form" \
  'EX="$(printf "%s" "$AI30" | sed -nE "s/.*for example \`(- [^\`]*)\`.*/\1/p")"; printf "%s\n" "$EX" | gq -xE -- "- [^-].* -- checks [A-Z0-9, -]*AI30[A-Z0-9, -]* -- left out [0-9]{4}-[0-9]{2}-[0-9]{2}" && row "$LO" "- [the item, in the words the user saw] -- checks [IDs, e.g. A01-A10, or none] -- left out [YYYY-MM-DD] [(taken out), only for a take-out]"'
check "with the line, AI30 reads Left out (your choice), never PASS or FAIL, and /ship-it names it; nothing else is an exception" \
  'has "$AI30" "With that line, AI30 reads **Left out (your choice)**, never PASS and never FAIL, and because AI30 is \`[BLOCK]\`, /ship-it names it in its high-stakes ask before production. No other note, comment or file makes an exception."'
check "AI30 says it is a tripwire that can be fooled both ways" \
  'has "$AI30" "AI30 is a tripwire, not proof: static detection can be fooled both ways -- a library or call under another name gets past it, and a name used for something else (a chart'"'"'s \`.fit(\`, a test that mocks embeddings) fails it."'
check "AI30 says it is a boundary check, not protection against poisoning" \
  'has "$AI30" "It is a boundary check: it shows the app holds none of these, and it does nothing to protect training data, a fine-tuned model or a retrieval store from poisoning once the user accepts one."'
check "AI30 says the CI half is not built" \
  'has "$AI30" "The CI half (the same scan in the organization'"'"'s pipeline, with its own exceptions list) is not built; only this build check exists."'
check "AI30 says the scaffolds as shipped have no hit" 'has "$AI30" "Both scaffolds as shipped have no hit."'

# 2. the patterns, on real sample lines
check "both patterns were found in AI30" '[ -n "$DEP" ] && [ -n "$CODE" ]'
pos_dep=(
  'chromadb==0.5.3'
  '    "@pinecone-database/pinecone": "^3.0.0",'
  'torch>=2.2'
  '  "qdrant-client>=1.9",'
  'faiss-cpu==1.8.0'
  'sentence-transformers==3.0.1'
  'pgvector==0.3.2'
  '    image: pgvector/pgvector:pg16'
  'RUN pip install --no-cache-dir scikit-learn'
  '    "@tensorflow/tfjs-node": "^4.20.0",'
  'transformers==4.44.0'
  '    "weaviate-client": "^3.1.0",'
  'llama-index==0.11.0'
)
neg_dep=(
  'anthropic>=0.40'
  'openai==1.51.0'
  'fastapi==0.115.0'
  'claude-agent-sdk>=0.2.186,<0.3'
  '    "next": "15.0.3",'
  '    "react": "19.0.0",'
  '    "@types/node": "^22",'
  'pdfplumber==0.11.4'
  'sqlalchemy[asyncio]==2.0.36'
  '    image: postgres:16-alpine'
  'RUN pip install --no-cache-dir -r requirements.txt'
)
pos_code=(
  '    model.fit(X_train, y_train)'
  'job = client.fine_tuning.jobs.create(training_file=f.id, model="gpt-4o-mini")'
  'const job = await openai.fineTuning.jobs.create({ training_file: id, model });'
  'resp = client.embeddings.create(model="text-embedding-3-small", input=text)'
  'trainer = Trainer(model=model, args=args, train_dataset=ds)'
  '        loss.backward()'
  'docs = store.similarity_search(query, k=4)'
  'CREATE EXTENSION IF NOT EXISTS vector;'
  'const { embeddings } = await embedMany({ model, values });'
  'result = genai.embed_content(model="models/text-embedding-004", content=text)'
  'emb = OpenAIEmbeddings(model="text-embedding-3-small")'
  'vector_store = Chroma(collection_name="docs")'
)
neg_code=(
  'resp = client.chat.completions.create(model=model, messages=msgs)'
  'msg = await client.messages.create(model=model, max_tokens=1024, messages=msgs)'
  '<img className="object-fit-cover" style={{ objectFit: "cover" }} />'
  'chart.fitView();'
  '    async def stream(self, system_prompt, user_prompt, model):'
  'const vector = [x, y];'
)
# the first positive of each kind is the one the card names; every sample must behave
miss=""; for l in "${pos_dep[@]}";  do [ "$(hits -Ei "$DEP" "$l")" = 1 ]  || miss="$miss | $l"; done
check "the dependency scan finds every positive sample (chromadb, Pinecone, torch, qdrant, faiss, pgvector, scikit-learn, TF.js, transformers, weaviate, llama-index)$miss" '[ -z "$miss" ]'
miss=""; for l in "${neg_dep[@]}";  do [ "$(hits -Ei "$DEP" "$l")" = 0 ]  || miss="$miss | $l"; done
check "the dependency scan finds none of the negative samples (anthropic, openai, the Claude SDK, next, react, postgres)$miss" '[ -z "$miss" ]'
miss=""; for l in "${pos_code[@]}"; do [ "$(hits -E "$CODE" "$l")" = 1 ]  || miss="$miss | $l"; done
check "the code scan finds every positive sample (.fit(, fine-tuning in Python and JS, embeddings calls, Trainer, backward, similarity search, pgvector SQL)$miss" '[ -z "$miss" ]'
miss=""; for l in "${neg_code[@]}"; do [ "$(hits -E "$CODE" "$l")" = 0 ]  || miss="$miss | $l"; done
check "the code scan finds none of the negative samples (chat completion, Claude messages, object-fit, fitView)$miss" '[ -z "$miss" ]'

# 3. the scaffolds as shipped (read from this repository, with the patterns of the tree being checked)
scan_scaffolds() {
  local f n=0 h=0 out=""
  [ -n "$DEP" ] && [ -n "$CODE" ] || return 1
  while IFS= read -r f; do
    case "$f" in
      */requirements*.txt|*/pyproject.toml|*/package.json|*/Dockerfile*|*/docker-compose*.yml|*/compose*.yml)
        n=$((n + 1)); h="$(grep -cEi -- "$DEP" "$root/$f" || true)" ;;
      *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.sql)
        n=$((n + 1)); h="$(grep -cE -- "$CODE" "$root/$f" || true)" ;;
      *) h=0 ;;
    esac
    [ "$h" = 0 ] || out="$out $f"
  done < <(git -C "$root" ls-files .claude/make-it/scaffolds)
  [ -z "$out" ] || echo "  hits in:$out"
  [ "$n" -gt 100 ] && [ -z "$out" ]
}
check "both scaffolds and the PWA overlay as shipped have no hit (over 100 files scanned)" 'scan_scaffolds'
check "the scan read each scaffold's dependency files" \
  'for f in fastapi-nextjs/backend/requirements.txt fastapi-nextjs/frontend/package.json nextjs-fullstack/package.json; do git -C "$root" ls-files --error-unmatch ".claude/make-it/scaffolds/$f" >/dev/null 2>&1 || exit 1; done'

# 4. no claim that CI enforces it, none that it protects against poisoning
# units: the lines that name AI30 or hold the rows it backs, cut at table cells, sentences, semicolons and " -- "
NEAR="$(cat $FILES | grep -E "AI30|Data Poisoning|RAG/vector DB guardrails" | perl -pe 's/\|/\n/g; s/([.!?;]) (?=\S)/$1\n/g; s/ -- /\n/g' || true)"
# "pipeline/" is agent composition (pipeline/delegation/fan-out), not CI
check "every unit near AI30 that names CI, a pipeline or make-it-verify says it is not built" \
  '! printf "%s\n" "$NEAR" | grep -E "\bCI\b|pipeline([^/]|\$)|make-it-verify|EXCEPTIONS[.]md" | gq -v "not built"'
# "not protection against poisoning" is the true sentence; any other protect/prevent/stop/... poisoning claim fails
check "no unit near AI30 says it protects against, prevents or stops poisoning" \
  '! printf "%s\n" "$NEAR" | perl -ne "\$n++ if /(?<!not )\b(protect|prevent|stop|block|guard|defend)[a-z]* (the app |apps )?(against |from )?(data (and model )?|model )?poisoning|poisoning (is )?(prevented|covered|mitigated|blocked)/i; END {exit(\$n ? 0 : 1)}"'

# 5. the governance document
R_AI04='| **AI04: Data Poisoning** | Not applicable: data and model poisoning targets training data, fine-tuning data and embedding or retrieval data, and make-it apps train no model, fine-tune none and add no retrieval. Check AI30 enforces it: it fails the build when the code adds model training, fine-tuning or retrieval, until the user accepts it in the app'"'"'s left-out record. AI30 is a tripwire (static detection can be fooled both ways) and a boundary check, not protection against poisoning; its CI half is not built. The prompt-management controls this row used to list (prompt template blocklist validation, immutable safety preamble, draft/test/publish workflow, risk_flag audit logging) guard the app'"'"'s own prompts against injected edits (AI03 above, section 5.3), not training or retrieval data. The optional AI memory layer (BN checks) puts stored memories into prompts by database query, with no embeddings; AI30 does not cover it | AI30 | Not applicable, enforced by check AI30 |'
R_AI08='| **AI08: Vector and Embedding Weaknesses** | Not yet applicable -- /make-it does not currently generate RAG/vector search applications, and check AI30 fails the build when the code adds embeddings or a vector store, until the user accepts it in the app'"'"'s left-out record. **Recommended:** Add vector DB guardrails when RAG variant is introduced | AI30 | Future |'
R_GAP='| **No RAG/vector DB guardrails** | Low (future) | Not applicable: make-it apps add no retrieval, and check AI30 fails the build when the code adds it, until the user accepts it in the app'"'"'s left-out record (a tripwire; its CI half is not built) | Plan vector DB security variant for /make-it |'
R_TAB='| AI Features | AI01-AI30 (incl. AI01a-AI01d) | 34 | AI (any type); AI30: 0 (Universal) |'
check "the AI04 row: not applicable, enforced by check AI30, the old controls moved and what they do cover" 'row "$GV" "$R_AI04"'
check "the AI04 row is not \"Yes\" again, and no row lists the prompt controls under Data Poisoning" \
  '! gq -E "^[|] [*][*]AI04: Data Poisoning[*][*] [|].*[|] (Yes|Partial) [|]\$" "$GV" && ! gq -F "| **AI04: Data Poisoning** | Prompt template" "$GV"'
check "the AI08 row and the RAG gap row name AI30" 'row "$GV" "$R_AI08" && row "$GV" "$R_GAP"'
check "the checks table reads AI01-AI30, 34, and its total is the sum of its rows" \
  'row "$GV" "$R_TAB" && T="$(awk -F"|" "/^## Appendix: Build Standards/ {on=1} on && \$4 ~ /^ [0-9]+ \$/ {s += \$4} END {print s}" "$GV")" && row "$GV" "| **Total** | | **~$T** | |"'

# 6. every AI range includes AI30
check "no range in the three commands or the two docs stops before AI30" \
  '[ "$(cat "$MK" "$RS" "$RF" "$GV" "$DV" | grep -cE "AI01-AI([0-9]|1[0-9]|2[0-9])([^0-9]|\$)" || true)" = 0 ]'
check "make-it.md: the AI range reads AI01-AI30 and says AI30 runs on every app" \
  '[ "$(grep -c "^- [*][*]AI01-AI30[*][*]: AI features (if ai_features.needed = true; AI30 runs on every app) -- " "$MK")" = 1 ] && gq -F "AI30 fails when the code adds model training, fine-tuning or retrieval (a tripwire);" "$MK"'
check "resume-it.md: the catch-up's AI range reads AI01-AI30 and runs AI30 on every app" \
  '[ "$(grep -c "^   - [*][*]AI (AI01-AI30):[*][*] Only if AI features detected, except AI30, which runs on every app -- " "$RS")" = 1 ]'
check "retrofit-it.md: the AI range reads AI01-AI30 and says AI30 runs on every app" \
  'row "$RF" "- **AI01-AI30**: AI features (if ai_features.needed = true; AI30 runs on every app)"'
check "DEVOPS-GUIDE.md: the AI range reads AI01-AI30" 'gq -F "AI safety (AI01-AI30)" "$DV"'

# 7. controls (this repo only): each opposite fails the checks above
if [ -z "${1:-}" ]; then
  # opp FILE PERL: a copy of the files with one edit must fail this script
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" && ! bash "$SELF" "$d" >/dev/null 2>&1
  }
  check "(control) an unchanged copy passes, so each control below fails for its own edit" \
    'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) fails with AI30 removed" 'opp "$BS" "s/^\*\*AI30\*\* [^\n]*\n//m"'
  check "(control) fails with AI30 downgraded to [WARN]" 'opp "$BS" "s/^\*\*AI30\*\* \[Tier 0\] \[BLOCK\]/**AI30** [Tier 0] [WARN]/m"'
  check "(control) fails with AI30 gated on ai_features.needed again" \
    'opp "$BS" "s/^\*\*AI30\*\* \[Tier 0\]/**AI30** [AI]/m" && opp "$BS" "s/It applies to every app, whatever \`ai_features.needed\` says: an app can add training or retrieval without that flag. //"'
  check "(control) fails with the exception route dropped (never passes)" \
    'opp "$BS" "s/[*][*]The accepted exception is the app.s left-out record[*][*].*?No other note, comment or file makes an exception. //"'
  check "(control) fails with the exception route opened up (any left-out line, or a code comment, passes)" \
    'opp "$BS" "s/ whose checks name AI30,/,/" && opp "$BS" "s/No other note, comment or file makes an exception./A comment in the code that names AI30 also makes an exception./" && opp "$BS" "s/AI30 reads [*][*]Left out \(your choice\)[*][*], never PASS and never FAIL/AI30 reads PASS/"'
  check "(control) fails with retrieval dropped from what it detects (vector stores, then embeddings calls)" \
    'opp "$BS" "s/\|chromadb//; s/\|\@pinecone-database\/pinecone//" && opp "$BS" "s/\|embeddings\\\\.create\\\\\(//"'
  check "(control) fails with training dropped from what it detects (.fit()" 'opp "$BS" "s/\\\\.fit\\\\\(\|//"'
  check "(control) fails with a pattern that hits ordinary code (chat completions)" 'opp "$BS" "s/\|fine_tuning\|/|fine_tuning|completions|/"'
  check "(control) fails with the tripwire sentence dropped, and with the boundary sentence dropped" \
    'opp "$BS" "s/AI30 is a tripwire, not proof: .*? fails it. //" && opp "$BS" "s/It is a boundary check: .*? once the user accepts one. //"'
  check "(control) fails with AI30 marked [SECURITY FIX]" 'opp "$BS" "s/^\*\*AI30\*\* \[Tier 0\] \[BLOCK\]/**AI30** [Tier 0] [BLOCK] [SECURITY FIX]/m"'
  check "(control) fails with the governance AI04 row claiming Yes again, and with the old row back" \
    'opp "$GV" "s/[|] AI30 [|] Not applicable, enforced by check AI30 [|]\$/| AI30 | Yes |/m" && opp "$GV" "s/^[|] [*][*]AI04: Data Poisoning[*][*] [|][^\n]*/| **AI04: Data Poisoning** | Prompt template blocklist validation; immutable safety preamble; draft\/test\/publish workflow; risk_flag audit logging | AI10 | Yes |/m"'
  check "(control) fails with a stale AI01-AI29 range back in make-it.md" 'opp "$MK" "s/^- \*\*AI01-AI30\*\*/- **AI01-AI29**/m"'
  check "(control) fails with a stale AI01-AI29 range back in resume-it.md" 'opp "$RS" "s/\*\*AI \(AI01-AI30\):\*\*/**AI (AI01-AI29):**/"'
  check "(control) fails with a stale AI01-AI29 range back in retrofit-it.md" 'opp "$RF" "s/^- \*\*AI01-AI30\*\*/- **AI01-AI29**/m"'
  check "(control) fails with a claim that CI enforces it (the governance row, then build-standards)" \
    'opp "$GV" "s/; its CI half is not built[.]/; the CI pipeline enforces it on every pull request./" && opp "$BS" "s/The CI half \(the same scan in the organization.s pipeline, with its own exceptions list\) is not built; only this build check exists./make-it-verify runs AI30 in CI too./"'
  check "(control) fails with a claim that AI30 protects against poisoning" \
    'opp "$GV" "s/a boundary check, not protection against poisoning/a boundary check that protects against poisoning/"'
  # L09-L11 (activity log: the user, the console log, the visitor's address) moved the total from 198 to 201; M05 (the practice sign-in's access code) to 202;
  # the Security row, once the no-Java row X04 was removed (2026-11-24), reads X01-X03, X05-X09, 8 (it had read X01-X06, 6): 204.
  check "(control) fails with the checks table count left at 33, and with the total left one short (203)" \
    'opp "$GV" "s/[|] AI01-AI30 \(incl. AI01a-AI01d\) [|] 34 [|]/| AI01-AI30 (incl. AI01a-AI01d) | 33 |/" && opp "$GV" "s/[*][*]~204[*][*]/**~203**/"'
fi

check "the whole run wrote nothing to stderr (a bad regex or an undefined helper fails here, not silently)" \
  '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
