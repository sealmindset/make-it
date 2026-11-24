#!/usr/bin/env bash
# Two small tooling contracts.
#   - sdd/scripts/task-brief takes a task number only: N goes into an awk regex and a file name, so every
#     argument that isn't 1 to 6 ASCII digits (and not zero) exits 2 with one plain message and writes nothing,
#     under every bash found here (macOS's 3.2 and a bash 5), and a plain number still extracts just that task.
#   - The backlog helpers (backlog/bin/*.py: card, check-plan, regen-board, scope, status, sync-prs) read and
#     write UTF-8 whatever the locale: every text-mode open() and every text=True subprocess call names
#     encoding='utf-8' (AST check), and each helper is RUN end to end on a temp board under
#     LC_ALL=C PYTHONUTF8=0 (Python's encoding there is ASCII) with a card title holding accents, CJK and an
#     emoji. Same run: a card starting with a BOM is found and written back without one; a card that isn't
#     UTF-8 is named and skipped by the listings and refused by a write (its bytes unchanged); a CRLF card
#     keeps CRLF on a one-field change; stdin that isn't UTF-8 is refused and leaves no temp file.
#     The run needs a Python that honours LC_ALL=C (Linux, CI, and macOS's python3 do); if the probe finds
#     one that doesn't, that part says SKIP and why instead of passing quietly. Windows is not checked here.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
check() { local name="$1"; shift; if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }

TB="$root/.claude/make-it/sdd/scripts/task-brief"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
printf '# Plan\n\n## Task 1: first\nalpha\n\n## Task 2: second\nbeta\n' > "$t/plan.md"

# every bash this machine has: macOS's /bin/bash is 3.2, CI's and a Linux container's are 5
bashes=""
for b in /bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash "$(command -v bash)"; do
  [ -x "$b" ] || continue
  v="$("$b" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
  case " $bashes " in *" $v="*) ;; *) bashes="$bashes $v=$b" ;; esac
done

# refused BASH N: exit status exactly 2, stderr exactly the one message, and no brief anywhere
refused() {
  local sh="$1" n="$2" rc=0 err want
  rm -rf "$t/.make-it"
  err="$(cd "$t" && "$sh" "$TB" "$t/plan.md" "$n" 2>&1 >/dev/null)" || rc=$?
  want="$(printf 'task-brief: N must be a task number (1 to 6 digits, not 0), got: %s' "$n")"
  [ "$rc" -eq 2 ] && [ "$err" = "$want" ] && [ -z "$(ls -A "$t/.make-it/sdd/briefs" 2>/dev/null)" ] \
    || { echo "  rc=$rc stderr=[$err]"; return 1; }
}
one() { local f; f="$(cd "$t" && "$1" "$TB" "$t/plan.md" "$2")" && grep -q '^beta$' "$f" && ! grep -q '^alpha$' "$f"; }
for pair in $bashes; do
  v="${pair%%=*}"; sh="${pair#*=}"
  # each argument a review tried; `-1` and `1 2` and a trailing newline catch a check that drops `^` or allows spaces
  for n in '../x' '/etc/passwd' '1; rm' '1 2' '-1' '٣' '１' '1e3' '1|.*' "$(printf '1\nx')" "1
" '' '0' '000' '1234567' '99999999999999999999' ' ' 'x1'; do
    check "bash $v: task-brief refuses N=$(printf '%q' "$n") with exit 2 and the plain message" refused "$sh" "$n"
  done
  check "bash $v: a task number still extracts only that task" one "$sh" 2
done
case "$bashes" in *" 3."*) ;; *) echo "note: no bash 3.2 here (macOS has it); checked with:$bashes" ;; esac

python3 -I - .claude/make-it/backlog/bin <<'PY' || fail=1
import ast, pathlib, sys
bad = []
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.py")):
    for n in ast.walk(ast.parse(p.read_text(encoding="utf-8"))):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        name = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
        kw = {k.arg for k in n.keywords}
        if any(k.arg == "text" and isinstance(k.value, ast.Constant) and k.value.value is True for k in n.keywords) and "encoding" not in kw:
            bad.append(f"{p.name}:{n.lineno} text=True with no encoding")
        if name not in ("open", "read_text", "write_text") or "encoding" in kw:
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
print(("ok   " if not bad else "FAIL ") + "every text-mode open/read_text/write_text and text=True subprocess call in backlog/bin names an encoding")
for b in bad:
    print("  " + b)
sys.exit(1 if bad else 0)
PY

# Each helper, run for real under an ASCII locale. The driver handles only bytes, so its own locale doesn't matter.
python3 -I - "$root/.claude/make-it/backlog/bin" "$t/board" <<'PY' || fail=1
import json, os, subprocess, sys
BIN, B = sys.argv[1], sys.argv[2]
env = {k: x for k, x in os.environ.items() if not k.startswith(('LC_', 'PYTHON'))}
env.update(LC_ALL='C', LANG='C', PYTHONUTF8='0', PYTHONCOERCECLOCALE='0', PYTHONDONTWRITEBYTECODE='1',
           GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t',
           GIT_CONFIG_COUNT='2', GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0='/dev/null',
           GIT_CONFIG_KEY_1='commit.gpgsign', GIT_CONFIG_VALUE_1='false')
probe = subprocess.run([sys.executable, '-c', 'import sys, locale; print(sys.stdout.encoding, locale.getpreferredencoding(False))'],
                       env=env, capture_output=True).stdout.decode().split()
if not probe or probe[0].lower() not in ('ascii', 'ansi_x3.4-1968', 'us-ascii'):
    print(f'SKIP the run under LC_ALL=C: this Python reports {probe}, not ASCII, so the locale case cannot show here'); sys.exit(0)
fails = []
def ok(name, cond, detail=b''):
    print(('ok   ' if cond else 'FAIL ') + name)
    if not cond: fails.append(name); print('  ' + (detail.decode('utf-8', 'backslashreplace') if isinstance(detail, bytes) else str(detail))[:600])
def run(tool, *args, stdin=b''):
    a = [os.fsencode(x) if isinstance(x, str) else x for x in args]
    return subprocess.run([sys.executable, os.path.join(BIN, tool), *a], input=stdin, env=env, capture_output=True, cwd=B)
U = lambda s: s.encode('utf-8')
title = 'Café naïve 日本語の題 🎉'
E, S = f'{B}/items/EPIC-01-x', f'{B}/items/EPIC-01-x/stories'
os.makedirs(S)
open(f'{E}/epic.md', 'wb').write(U('---\nid: E01\ntitle: Épique 中文 ✨\nstatus: in-progress\n---\n'))
subprocess.run(['git', 'init', '-q', B], check=True, env=env)
subprocess.run(['git', '-C', B, 'add', '-A'], check=True, env=env)
subprocess.run(['git', '-C', B, 'commit', '-qm', 'seed'], check=True, env=env)
tmps = lambda: [f for f in os.listdir(S) if f.endswith('.tmp')]
card = lambda n: f'{S}/{n}'
r = run('card.py', '--board', B, 'new', 'E01', stdin=U(f'---\nid: NEW\ntitle: "{title}"\ntype: breakfix\nstatus: backlog\ncategory: Ménage\n---\n\n## Goal\nrésumé 中文 🚀\n'))
new = [f for f in os.listdir(S) if f.startswith('S1-')]
ok('card.py new: exit 0, says the new card, commits, writes the title as UTF-8', r.returncode == 0 and U(f'new E01-S1: "{title}" · committed') in r.stdout
   and len(new) == 1 and U(title) in open(card(new[0]), 'rb').read(), r.stdout + r.stderr)
S1 = card(new[0]) if new else card('missing')
log = subprocess.run(['git', '-C', B, 'log', '-1', '--format=%s'], capture_output=True, env=env).stdout
ok('card.py new: the commit message holds the title', U('Café') in log, log)
r = run('card.py', '--board', B, 'set', 'E01-S1', 'signal=page shows « Café 日本 » ✓ 🎉')
ok('card.py set: a non-ASCII value from the command line is written as UTF-8', r.returncode == 0 and U('signal: page shows « Café 日本 » ✓ 🎉\n') in open(S1, 'rb').read(), r.stdout + r.stderr)
r = run('card.py', '--board', B, 'append', 'E01-S1', 'Notes é', stdin=U('- naïve 中文 🚀\n'))
ok('card.py append: exit 0 and the text lands under a non-ASCII section name', r.returncode == 0 and U('## Notes é\n- naïve 中文 🚀') in open(S1, 'rb').read(), r.stdout + r.stderr)
before = open(S1, 'rb').read()
r = run('card.py', '--board', B, 'append', 'E01-S1', 'Notes', stdin=b'- bad \xff\xfe bytes\n')
ok('card.py append: stdin that is not UTF-8 is refused in plain words, card unchanged, no temp file',
   r.returncode != 0 and b'not UTF-8' in r.stderr and b'Traceback' not in r.stderr and open(S1, 'rb').read() == before and not tmps(), r.stderr)
r = run('card.py', '--board', B, 'set', 'E01-S1', b'signal=bad \xff bytes')
ok('card.py set: a value that is not UTF-8 is refused, card unchanged, no temp file',
   r.returncode != 0 and b'not UTF-8' in r.stderr and b'Traceback' not in r.stderr and open(S1, 'rb').read() == before and not tmps(), r.stderr)
# the three odd cards: a BOM, a byte that isn't UTF-8, CRLF line endings
open(card('S7-bom.md'), 'wb').write(b'\xef\xbb\xbf' + U('---\nid: E01-S7\ntitle: Bom ✓\nstatus: backlog\n---\n'))
BAD = card('S8-bad.md'); bad = b'---\nid: E01-S8\ntitle: Latin-1 caf\xe9\nstatus: backlog\n---\n'
open(BAD, 'wb').write(bad)
open(card('S9-crlf.md'), 'wb').write(U('---\r\nid: E01-S9\r\ntitle: Crlf é\r\nstatus: backlog\r\n---\r\n\r\n## Notes\r\nkeep\r\n'))
named = lambda r: b'S8-bad.md' in r.stderr and b'not UTF-8' in r.stderr and b'Traceback' not in r.stderr
r = run('card.py', '--board', B, 'set', 'E01-S7', 'size=S')
c = open(card('S7-bom.md'), 'rb').read()
ok('card.py set: a card starting with a BOM is found and written back without one', r.returncode == 0 and c.startswith(b'---\n') and b'size: S\n' in c, r.stdout + r.stderr)
r = run('card.py', '--board', B, 'set', 'E01-S9', 'size=M')
c = open(card('S9-crlf.md'), 'rb').read()
ok('card.py set: a CRLF card keeps CRLF on a one-field change', r.returncode == 0 and b'size: M\r\n' in c and c.count(b'\n') == c.count(b'\r\n') and c.endswith(b'keep\r\n'), c)
r = run('card.py', '--board', B, 'set', 'E01-S8', 'size=L')
ok('card.py set: a card that is not UTF-8 is refused, named, its bytes unchanged', r.returncode != 0 and named(r) and open(BAD, 'rb').read() == bad and not tmps(), r.stderr)
r = run('regen-board.py', B)
board = open(f'{B}/BOARD.md', 'rb').read()
ok('regen-board.py: exit 0, names and skips the bad card, BOARD.md is UTF-8 with the title', r.returncode == 0 and named(r) and U(title) in board and U('E01-S7 · Bom ✓') in board, r.stderr)
r = run('status.py', B)
ok('status.py: exit 0, prints the report (—, ·) and names the bad card', r.returncode == 0 and U('BOARD STATUS — ') in r.stdout and U('Café') in r.stdout and named(r), r.stdout[-300:] + r.stderr)
r = run('sync-prs.py', B)
ok('sync-prs.py: exit 0, prints its report (·) and names the bad card', r.returncode == 0 and U(' · ') in r.stdout and named(r), r.stdout + r.stderr)
r = run('scope.py', B, 'ménage')
ok('scope.py: a non-ASCII category filter from the command line finds the card; the bad card is named',
   r.returncode == 0 and json.loads(r.stdout)['in_filter'] == ['E01-S1'] and named(r), r.stdout + r.stderr)
open(f'{B}/plan.json', 'wb').write(U(json.dumps({'waves': [{'items': [{'id': 'E01-S1', 'mode': 'solo'}]}], 'held': [{'id': 'E01-S7', 'why': 'attente — 日本'}]}, ensure_ascii=False)))
r = run('check-plan.py', B, f'{B}/plan.json', '--partial')
ok('check-plan.py: exit 0 on a UTF-8 plan, the bad card named', r.returncode == 0 and b'plan OK' in r.stdout and named(r), r.stdout + r.stderr)
ok('no temp file left anywhere on the board', not tmps(), os.listdir(S))
sys.exit(1 if fails else 0)
PY

for s in card check-plan regen-board scope status sync-prs; do
  check "backlog/bin/$s.py --self-test" python3 -I ".claude/make-it/backlog/bin/$s.py" --self-test
done
exit "$fail"
