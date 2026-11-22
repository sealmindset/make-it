#!/usr/bin/env bash
# Two small tooling contracts.
#   - sdd/scripts/task-brief takes a task number only: N goes into an awk regex and a file name, so `1|.*`
#     (every heading, the whole plan) and `../x` (a path outside the briefs folder) are refused, and a plain
#     number still extracts just that task.
#   - Every text-mode open(), read_text() and write_text() in backlog/bin/*.py names encoding='utf-8', so card
#     text with non-ASCII characters reads and writes the same on every machine, whatever its locale.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
check() { local name="$1"; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }

TB="$root/.claude/make-it/sdd/scripts/task-brief"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
printf '# Plan\n\n## Task 1: first\nalpha\n\n## Task 2: second\nbeta\n' > "$t/plan.md"
refused() { ( cd "$t" && ! "$TB" "$t/plan.md" "$1" >/dev/null 2>&1 ) && [ ! -e "$t/.make-it/sdd/briefs/task-$1-brief.md" ]; }
check "a regex in N is refused, and no brief is written" refused '1|.*'
check "a path in N is refused" refused '../x'
check "an empty-looking N is refused" refused ' '
one() { local f; f="$(cd "$t" && "$TB" "$t/plan.md" 2)" && grep -q '^beta$' "$f" && ! grep -q '^alpha$' "$f"; }
check "a task number still extracts only that task" one

python3 -I - .claude/make-it/backlog/bin <<'PY' || fail=1
import ast, pathlib, sys
bad = []
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.py")):
    for n in ast.walk(ast.parse(p.read_text(encoding="utf-8"))):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        name = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
        if name not in ("open", "read_text", "write_text") or any(k.arg == "encoding" for k in n.keywords):
            continue
        if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "os":
            continue
        mode = None
        if name == "open":
            pos = 1 if isinstance(f, ast.Name) else 0
            if len(n.args) > pos and isinstance(n.args[pos], ast.Constant):
                mode = n.args[pos].value
            mode = next((k.value.value for k in n.keywords if k.arg == "mode" and isinstance(k.value, ast.Constant)), mode)
        if mode is not None and "b" in str(mode):
            continue
        bad.append(f"{p.name}:{n.lineno} {name}()")
print(("ok   " if not bad else "FAIL ") + "every text-mode open/read_text/write_text in backlog/bin names encoding='utf-8'")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
PY

for s in card check-plan regen-board scope status sync-prs; do
  check "backlog/bin/$s.py --self-test" python3 -I ".claude/make-it/backlog/bin/$s.py" --self-test
done
exit "$fail"
