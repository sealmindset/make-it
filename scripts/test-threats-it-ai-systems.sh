#!/usr/bin/env bash
# /threats-it treats the organisation's own AI systems as a target (owner, 2026-11-17).
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
T=.claude/make-it/threats-it
python3 -I - "$T/templates/presence-ai.json" <<'PY' || fail=1
import json, re, sys
p, bad = json.load(open(sys.argv[1])), 0
def check(name, ok):
    global bad
    print(("ok   " if ok else "FAIL ") + name); bad |= not ok
check("every entry has the four keys exposure.py reads", all(set(v) == {"app_names", "arm_publisher", "arm_offer", "arm_type"} for v in p.values()))
check("every pattern is a regex both Python and KQL accept (no look-around)", all(re.compile(x) and "(?" not in x for v in p.values() for x in v.values() if x))
def app(name): return [k for k, v in p.items() if v["app_names"] and re.search(v["app_names"], name, re.I)]
def arm(t): return [k for k, v in p.items() if v["arm_type"] and re.search(v["arm_type"], t, re.I)]
for name in ("Microsoft 365 Copilot", "Azure OpenAI Service", "ChatGPT Enterprise", "Claude for Work", "Copilot Studio Agent", "Contoso MCP Server", "HR Agent"):
    check(f"an app named '{name}' is found", bool(app(name)))
for name in ("Salesforce", "Palo Alto GlobalProtect", "Management Console", "Agents of Change Fund"):
    check(f"an app named '{name}' is not found", not app(name))
for t in ("microsoft.cognitiveservices/accounts", "Microsoft.MachineLearningServices/workspaces", "microsoft.botservice/botservices"):
    check(f"a resource of type {t} is found", bool(arm(t)))
check("an ordinary resource type is not found", not arm("microsoft.compute/virtualmachines") and not arm("microsoftXcognitiveservices/accounts"))
sys.exit(bad)
PY
R=$T/references
flat() { tr '\n' ' ' | tr -s ' '; }
has() { if [ "$(flat < "$2" | grep -cF -- "$1")" -gt 0 ]; then echo "ok   $3"; else echo "FAIL $3"; fail=1; fi; }
A=$R/ai-systems.md
has 'is an identity with standing access that takes instructions from what it reads' "$A" "an AI system is treated as a privileged identity"
has 'A name match is a name hint' "$A" "a name match alone is not presence"
has 'What does it read that outsiders can write?' "$A" "outsider-writable inputs are inventoried"
has 'What can it do with nobody approving?' "$A" "unapproved actions are inventoried"
has '"Not visible" is not "none"' "$A" "what cannot be seen is said"
has 'all three is a path with one link' "$A" "private data plus outside content plus a way to act is called out"
has 'It never sends a prompt to the organisation' "$A" "the skill never prompts an AI system"
has 'never plants content for one to read' "$A" "the skill never plants content"
has 'It never reports a prompt or a payload that would work' "$A" "no working prompt is reported"
has 'never cite one from memory' "$A" "ATLAS ids are verified, not recalled"
has 'It never calls an AI system vulnerable because of what such systems can do in general' "$A" "a finding needs evidence about this system"
has 'Instruction planted in content an agent reads' "$R/attack-chains.md" "the planted-instruction pattern is listed"
has 'Poisoned skill, plugin or MCP server' "$R/attack-chains.md" "the poisoned-tool pattern is listed"
has 'references/ai-systems.md' .claude/commands/threats-it.md "the skill follows the AI systems step"
has 'Never prompt one' .claude/commands/threats-it.md "the skill's step keeps the no-prompt rule"
has 'one called present from its name alone' "$R/fact-check.md" "the fact-check looks for name-only presence"
exit $fail
