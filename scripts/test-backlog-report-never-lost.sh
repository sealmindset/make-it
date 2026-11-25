#!/usr/bin/env bash
# A report given to /backlog-it always becomes a card, and a card write says truly whether it reached the shared board.
# Proven by RUNNING card.py on stand-in boards (scripts/backlog-stand-in/make-board.py: a temp git repo) with a
# local bare repo as the shared board. No AI call, no network, no real board.
#   - `card.py capture [triage-file]` (the report on stdin) is where the fallback lives. Every kind of bad triage
#     output -- prose, empty, a refusal, none at all (a timeout), JSON that is not an object, missing or bad
#     fields, an epic that is not on the board -- leaves a card under the Bugs epic (made when the board has
#     none), as a bug at Reported, saying "not sorted yet" and "triage failed: <reason>", holding the report
#     word for word: odd characters, lines that look like a card's own markup, a very long report, bytes that are
#     not UTF-8. Good triage output writes nothing and says so: the skill then writes the sorted card with `new`.
#   - The result line is true. Sent means the shared board has the commit. Not sent says "NOT sent to", why, and:
#     exit 0 when the board has no shared copy to send to (no remote, inside a project, not in git, --no-sync);
#     exit 3 when it has one and the card did not get there (the branch follows nothing, the push was refused,
#     the pull failed, the repo is not on a branch); exit 1 only when nothing was written.
#   - A card that was not sent goes with the next write that can send, also when the shared board moved meanwhile.
#   - Two clones that file a card at the same moment end with two cards, two ids, both on the shared board.
#   - The skill and its reference send a failed triage to `card.py capture` and relay a card that was not sent.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
python3 -I - "$root" "$t" <<'PY'
import json, os, re, shutil, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
CARD, STAND = f'{root}/.claude/make-it/backlog/bin/card.py', f'{root}/scripts/backlog-stand-in'
fail = 0
def ok(name, cond, detail=''):
    global fail
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else f'\n     {str(detail)[-900:]}'))
    fail |= not cond
def git(d, *a, check=True):
    return subprocess.run(['git', '-C', d, *a], capture_output=True, text=True, encoding='utf-8', check=check).stdout.strip()
def card(B, *a, stdin=b''):
    r = subprocess.run([sys.executable, CARD, '--board', B, '--project', 'stand-in', *a], input=stdin if isinstance(stdin, bytes) else stdin.encode('utf-8'), capture_output=True)
    return r.returncode, r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace')
n = [0]
def shared():
    """A stand-in board that follows a shared board (a local bare repo). Returns (board, shared board)."""
    n[0] += 1; d = f'{tmp}/s{n[0]}'
    subprocess.run([sys.executable, f'{STAND}/make-board.py', d], check=True)
    subprocess.run(['git', 'init', '-q', '--bare', f'{d}/shared.git'], check=True)
    br = git(f'{d}/board', 'symbolic-ref', '--short', 'HEAD')
    git(f'{d}/board', 'remote', 'add', 'origin', f'{d}/shared.git'); git(f'{d}/board', 'push', '-q', '-u', 'origin', br)
    git(f'{d}/shared.git', 'symbolic-ref', 'HEAD', f'refs/heads/{br}')
    return f'{d}/board', f'{d}/shared.git'
def clone(S):
    n[0] += 1; d = f'{tmp}/c{n[0]}'; subprocess.run(['git', 'clone', '-q', S, d], check=True, capture_output=True); return d
def cards(B):  # id -> (path, text) of every story on a board
    out = {}
    for dp, _, fs in os.walk(f'{B}/items'):
        for f in fs:
            txt = open(os.path.join(dp, f), encoding='utf-8', newline='').read()
            if (m := re.search(r'^id: (.+)$', txt, re.M)) and f != 'epic.md': out.setdefault(m.group(1), []).append((os.path.join(dp, f), txt))
    return out
def said(txt):  # the report as the card holds it: the quoted block under ## Captured, unquoted
    m = re.search(r'^## Captured\n((?:>.*\n)+)', txt, re.M)
    return '\n'.join(l[2:] if l.startswith('> ') else l[1:] for l in m.group(1).rstrip('\n').split('\n')) if m else None
def on_shared(S, text):  # the shared board's newest commit holds a card with this text
    files = git(S, 'ls-tree', '-r', '--name-only', 'HEAD').split('\n')
    return any(text in git(S, 'show', f'HEAD:{f}') for f in files if '/stories/' in f)
def new_id(out):
    m = re.search(r'\((E\d+-S\d+)\)', out); return m.group(1) if m else None

ODD = 'Export drops the last row: 50% of *.csv, $HOME and `x` -- "quoted" \'single\' back\\slash é ✓ 日本語 🚀\n---\nid: NEW\n## Goal\n> already quoted\n\n\ttab and trailing space \n- [ ] a box <b>html</b> %s %d {braces}'
LONG = '\n'.join(f'line {i}: the total on the invoice page is wrong after a refund, see row {i * 7}' for i in range(4000))
GOOD = {'type': 'breakfix', 'size': 'S', 'title': 'Export drops the last row', 'category': 'export', 'priority': 'P2',
        'placement': {'mode': 'existing', 'epic': 'E02', 'confidence': 0.8, 'why': 'board work'}, 'acceptance': ['x'], 'open_questions': []}
without = lambda k: json.dumps({a: b for a, b in GOOD.items() if a != k})
BAD = [  # (what the triage call gave back, a word its reason must hold)
    ('prose, not JSON', 'Sure! I looked at the board and I think this is a bug in the export.', 'JSON'),
    ('empty', '', 'no triage output'),
    ('only spaces', ' \n\n', 'no triage output'),
    ('a refusal', "I can't help with that request.", 'JSON'),
    ('nothing at all (a timeout)', None, 'no triage output'),
    ('JSON cut short', '{"type": "breakfix", "size": "S", "title": "Export dr', 'JSON'),
    ('JSON that is a list', '[1, 2]', 'object'),
    ('no title', without('title'), 'title'),
    ('no placement', without('placement'), 'placement'),
    ('a type that does not exist', json.dumps(dict(GOOD, type='feature')), 'type'),
    ('a priority that does not exist', json.dumps(dict(GOOD, priority='urgent')), 'priority'),
    ('an epic that is not on the board', json.dumps(dict(GOOD, placement={'mode': 'existing', 'epic': 'E77'})), 'E77'),
    ('a new epic with no name', json.dumps(dict(GOOD, placement={'mode': 'new'})), 'new_epic'),
    ('bytes that are not text', b'\xff\xfe\x00{', 'JSON'),
]

# ---- 1. bad triage output: the report is a card anyway -------------------------------------------------------
B, S = shared()
for i, (kind, triage, word) in enumerate(BAD):
    report = [ODD, LONG, 'One line.'][i % 3] + f'\n(report {i})'
    f = f'{tmp}/triage{i}'
    if triage is not None: open(f, 'wb').write(triage if isinstance(triage, bytes) else triage.encode('utf-8'))
    before = set(cards(B))
    rc, out, err = card(B, 'capture', *([f] if triage is not None else []), stdin=report)
    new = [c for c in cards(B) if c not in before]
    c = cards(B)[new[0]][0] if len(new) == 1 else ('', '')
    good = (rc == 0 and len(new) == 1 and '/EPIC-01-bugs/stories/' in c[0] and said(c[1]) == report
            and all(re.search(p, c[1], re.M) for p in (r'^type: breakfix$', r'^status: backlog$', r'^stage: Reported$', r'^parent: E01$'))
            and 'not sorted yet' in c[1] and re.search(rf'triage failed: .*{re.escape(word)}', c[1]) and re.search(rf'triage failed: .*{re.escape(word)}', out)
            and f'({new[0]})' in out and 'committed + pushed' in out and on_shared(S, f'(report {i})'))
    ok(f'triage gave back {kind}: the report is a card under Bugs, word for word, and on the shared board', good, f'rc={rc}\n{out}\n{err}\n{c[1][:400]}')
ids = [i for i, v in cards(B).items() for _ in v]
ok('every card has its own id, and each can be written to afterwards', len(ids) == len(set(ids)) and card(B, 'set', ids[-1], 'size=S')[0] == 0, ids)
ok('the board page lists the unsorted reports', 'One line.' in open(f'{B}/BOARD.md', encoding='utf-8').read())

rc, out, err = card(B, 'capture', stdin=b'The caf\xe9 page crashes \xff here')  # not UTF-8: kept as far as it can be read
c = [x for v in cards(B).values() for x in v if 'page crashes' in x[1]]
ok('a report that is not UTF-8 still becomes a card', rc == 0 and len(c) == 1 and 'The caf' in c[0][1] and 'here' in c[0][1], f'{rc} {out} {err}')
rc, out, err = card(B, 'capture', stdin='  \n')
ok('an empty report is refused in plain words (there is nothing to keep)', rc == 1 and 'empty' in err, f'{rc} {out} {err}')

for kind, text in (('good triage output', json.dumps(GOOD)), ('good triage output inside a code fence', '```json\n' + json.dumps(GOOD) + '\n```\n')):
    open(f'{tmp}/good', 'w', encoding='utf-8').write(text); before = set(cards(B)); head = git(B, 'rev-parse', 'HEAD')
    rc, out, err = card(B, 'capture', f'{tmp}/good', stdin='A sorted report.')
    ok(f'{kind}: nothing is written, and the line says the sorted card is still to be written',
       rc == 0 and out.startswith('triage ok') and 'nothing written' in out and set(cards(B)) == before and git(B, 'rev-parse', 'HEAD') == head, f'{rc} {out} {err}')

os.makedirs(f'{tmp}/nobugs/items/EPIC-01-shop/stories')  # a board with no Bugs epic, and not in git
open(f'{tmp}/nobugs/items/EPIC-01-shop/epic.md', 'w', encoding='utf-8').write('---\nid: E01\ntitle: Shop\ntype: epic\nstatus: in-progress\n---\n')
rc, out, err = card(f'{tmp}/nobugs', 'capture', stdin=ODD)
c = [x for v in cards(f'{tmp}/nobugs').values() for x in v]
ep = [open(os.path.join(dp, 'epic.md'), encoding='utf-8').read() for dp, _, fs in os.walk(f'{tmp}/nobugs/items') if 'epic.md' in fs and 'shop' not in dp]
ok('a board with no Bugs epic gets one, and the report goes under it', rc == 0 and len(c) == 1 and said(c[0][1]) == ODD and len(ep) == 1
   and re.search(r'^id: E02$', ep[0], re.M) and re.search(r'^title: Bugs$', ep[0], re.M) and re.search(r'^parent: E02$', c[0][1], re.M), f'{rc} {out} {err} {ep}')
ok('a board that is not in git: written, and the line says it went to no shared board', 'NOT sent to a shared board' in out and 'not in git' in out, out)

# ---- 2. the result line is true ------------------------------------------------------------------------------
NOT = 'NOT sent to the shared board'
B, S = shared()
rc, out, err = card(B, 'set', 'E01-S2', 'size=M')
ok('sent: the line says so and the shared board has the commit', rc == 0 and 'committed + pushed' in out and 'NOT sent' not in out and git(S, 'rev-parse', 'HEAD') == git(B, 'rev-parse', 'HEAD'), f'{rc} {out} {err}')

L = f'{tmp}/local'; subprocess.run([sys.executable, f'{STAND}/make-board.py', L], check=True); L += '/board'  # its own repo, no remote
rc, out, err = card(L, 'set', 'E01-S2', 'size=M')
ok('a board with no remote: "not shared yet", exit 0', rc == 0 and 'committed here, NOT sent to a shared board' in out and 'not shared yet' in out and 'Totals are wrong after a refund (E01-S2)' in out, f'{rc} {out} {err}')
subprocess.run(['git', 'init', '-q', '--bare', f'{tmp}/late.git'], check=True); git(L, 'remote', 'add', 'origin', f'{tmp}/late.git')
rc, out, err = card(L, 'capture', stdin='A remote was added but never pushed to.')
ok('a remote the branch does not follow: the card is written, the line says it was not sent and how to fix it, exit 3',
   rc == 3 and NOT in out and 'push -u' in out and re.search(r'^new: A remote was added but never pushed to\. \(E01-S\d+\)', out) and NOT in err, f'{rc} {out} {err}')
git(L, 'push', '-q', '-u', 'origin', git(L, 'symbolic-ref', '--short', 'HEAD'))
ok('after that fix the next write is sent', card(L, 'set', 'E01-S2', 'size=S')[0] == 0 and on_shared(f'{tmp}/late.git', 'A remote was added but never pushed to.'))

rc, out, err = card(B, '--no-sync', 'set', 'E01-S2', 'size=L')
ok('--no-sync: written, the line says it was not sent, exit 0', rc == 0 and NOT in out and '--no-sync' in out, f'{rc} {out} {err}')
card(B, 'set', 'E01-S2', 'size=L')

P = f'{tmp}/proj'; os.makedirs(f'{P}/.claude'); subprocess.run(['git', 'init', '-q', P], check=True)  # a board inside a project
shutil.copytree(f'{B}/items', f'{P}/.claude/backlog/items')
rc, out, err = card(f'{P}/.claude/backlog', 'capture', stdin='A report on a project board.')
ok('a board inside a project: staged, the line says it went to no shared board and what carries it, exit 0',
   rc == 0 and 'staged, NOT sent to a shared board' in out and 'next commit' in out and 'stories/' in git(P, 'diff', '--cached', '--name-only'), f'{rc} {out} {err}')

hook = f'{S}/hooks/pre-receive'; open(hook, 'w', encoding='utf-8').write('#!/bin/sh\necho "the shared board refuses pushes today" >&2\nexit 1\n'); os.chmod(hook, 0o755)
rc, out, err = card(B, 'capture', stdin='Refused report.\n' + ODD)
c = [x for v in cards(B).values() for x in v if 'Refused report.' in x[1]]
ok('the shared board refuses the push: the card is here and committed, the line says it was not sent and why, exit 3',
   rc == 3 and len(c) == 1 and 'committed here, ' + NOT in out and 'push' in out and re.search(r'^new: Refused report\. \(E01-S\d+\)', out) and NOT in err
   and not git(B, 'status', '--porcelain', '--', 'items') and not on_shared(S, 'Refused report.'), f'{rc} {out} {err}')
rc, out, err = card(B, 'set', 'E01-S2', 'size=M')
ok('a second write while it still refuses: again not sent, exit 3, never "pushed"', rc == 3 and NOT in out and 'pushed' not in out, f'{rc} {out} {err}')
os.remove(hook)
rc, out, err = card(B, 'set', 'E01-S2', 'size=M')  # the same value: nothing new to commit, but two commits wait
ok('once it accepts again, the very next write carries the waiting card across (even one that changes nothing)',
   rc == 0 and 'NOT sent' not in out and on_shared(S, 'Refused report.') and git(S, 'rev-parse', 'HEAD') == git(B, 'rev-parse', 'HEAD'), f'{rc} {out} {err}')

os.rename(S, S + '.away')  # the shared board cannot be reached: the pull fails
before = open(cards(B)['E01-S2'][0][0], encoding='utf-8').read()
rc, out, err = card(B, 'set', 'E01-S2', 'size=XL')
ok('the pull fails on a change to a card: nothing written, said so, exit 1', rc == 1 and 'nothing written' in err and open(cards(B)['E01-S2'][0][0], encoding='utf-8').read() == before, f'{rc} {out} {err}')
rc, out, err = card(B, 'capture', stdin='Offline report.')
c = [x for v in cards(B).values() for x in v if 'Offline report.' in x[1]]
ok('the pull fails on a report: the card is written and committed here, the line says it was not sent, exit 3',
   rc == 3 and len(c) == 1 and NOT in out and re.search(r'^new: Offline report\. \(E01-S\d+\)', out), f'{rc} {out} {err}')
os.rename(S + '.away', S)
other = clone(S); r2 = card(other, 'capture', stdin='Filed from another machine meanwhile.')  # the shared board moves on
rc, out, err = card(B, 'set', 'E01-S2', 'size=XL')
allc = cards(B); ids = [i for i, v in allc.items() for _ in v]
ok('back in reach, and the shared board moved meanwhile: the next write puts ours on top and sends both',
   r2[0] == 0 and rc == 0 and 'committed + pushed' in out and on_shared(S, 'Offline report.') and on_shared(S, 'Filed from another machine meanwhile.')
   and len(ids) == len(set(ids)) and git(S, 'rev-parse', 'HEAD') == git(B, 'rev-parse', 'HEAD'), f'{r2}\n{rc} {out} {err}\n{sorted(ids)}')

git(B, 'checkout', '-q', '--detach')
rc, out, err = card(B, 'capture', stdin='Report while the board repo is not on a branch.')
c = [x for v in cards(B).values() for x in v if 'not on a branch.' in x[1]]
ok('the board repo is not on a branch: the report is still written here, the line says it was not sent, exit 3', rc == 3 and len(c) == 1 and NOT in out, f'{rc} {out} {err}')

# ---- 3. two clones file a card at the same moment ------------------------------------------------------------
B, S = shared(); A2 = clone(S)
# B's push waits until A2 has filed and pushed its own card: both took the same next id from the same board
hook = f'{B}/.git/hooks/pre-push'
open(hook, 'w', encoding='utf-8').write(f'#!/bin/sh\n[ -e "{tmp}/raced" ] && exit 0\n: > "{tmp}/raced"\nunset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE\n'
                                        f'printf "Second writer, same moment." | "{sys.executable}" "{CARD}" --board "{A2}" capture > "{tmp}/second.out" 2>&1\nexit 0\n')
os.chmod(hook, 0o755)
rc, out, err = card(B, 'capture', stdin='First writer, same moment.')
second = open(f'{tmp}/second.out', encoding='utf-8').read() if os.path.exists(f'{tmp}/second.out') else 'the second writer never ran'
allc = cards(B); ids = [i for i, v in allc.items() for _ in v]; mine = new_id(out)
ok('two writers at once: both lines true, two cards with two ids, both on the shared board',
   rc == 0 and 'committed + pushed' in out and 'committed + pushed' in second and len(ids) == len(set(ids)) and mine and new_id(second) and mine != new_id(second)
   and mine in allc and 'First writer, same moment.' in allc[mine][0][1] and on_shared(S, 'First writer, same moment.') and on_shared(S, 'Second writer, same moment.')
   and git(S, 'rev-parse', 'HEAD') == git(B, 'rev-parse', 'HEAD') and f'is now {mine}' in git(S, 'log', '-1', '--format=%s'), f'{rc} {out} {err}\n{second}\n{sorted(ids)}')
ps = [subprocess.Popen([sys.executable, CARD, '--board', b, 'capture'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for b in (B, A2) for _ in range(3)]
outs = [(q.communicate(f'Burst report {i}.'.encode())[0].decode(), q.returncode) for i, q in enumerate(ps)]
for b in (B, A2, B): last = card(b, 'set', 'E01-S2', 'size=M')  # one more write from each sends whatever still waits
allc = cards(B); ids = [i for i, v in allc.items() for _ in v]
ok('six reports from two clones in one burst: every line true (sent, or not sent with exit 3), none lost, no id twice, all on the shared board in the end',
   all((rc == 0 and 'committed + pushed' in o) or (rc == 3 and NOT in o) for o, rc in outs) and last[0] == 0 and len(ids) == len(set(ids))
   and all(on_shared(S, f'Burst report {i}.') for i in range(6)), f'{outs}\n{last}\n{sorted(ids)}')

# ---- 3b. review round: nothing saved here is left behind, and nothing is renumbered silently -------------------
NEWC = lambda title, body='x': f'---\nid: NEW\ntitle: "{title}"\ntype: story\nstatus: backlog\n---\n\n## Goal\n{body}\n'
refuse = lambda S: (open(f'{S}/hooks/pre-receive', 'w', encoding='utf-8').write('#!/bin/sh\necho "refused today" >&2\nexit 1\n'), os.chmod(f'{S}/hooks/pre-receive', 0o755))
def board_true(S):  # the shared BOARD.md lists no card the shared board does not hold
    ids = set(re.findall(r'^id: (\S+)', '\n'.join(git(S, 'show', f'HEAD:{f}') for f in git(S, 'ls-tree', '-r', '--name-only', 'HEAD').split('\n') if f.startswith('items/')), re.M))
    return all(i in ids for i in re.findall(r'\bE\d+-S\d+\b', git(S, 'show', 'HEAD:BOARD.md')))

B, S = shared(); git(B, 'checkout', '-q', '--detach')
r1 = card(B, 'capture', stdin='Report while detached.')
git(B, 'checkout', '-q', '-')
open(f'{B}/items/EPIC-01-bugs/stories/notes.txt', 'w', encoding='utf-8').write('my own notes\n')      # not a card: never taken along
open(f'{B}/items/EPIC-01-bugs/stories/draft.md', 'w', encoding='utf-8').write('a draft with no frontmatter\n')
r2 = card(B, 'set', 'E01-S2', 'size=M')
left = git(B, 'ls-files', '--others', '--exclude-standard', '--', 'items').split('\n')
ok('a card written while the repo was not on a branch goes with the next write, and only card files are taken along',
   r1[0] == 3 and r2[0] == 0 and 'committed + pushed' in r2[1] and on_shared(S, 'Report while detached.') and board_true(S)
   and sorted(os.path.basename(f) for f in left) == ['draft.md', 'notes.txt'], f'{r1}\n{r2}\n{left}')

B, S = shared(); hook = f'{B}/.git/hooks/pre-commit'
open(hook, 'w', encoding='utf-8').write('#!/bin/sh\necho "no commits today" >&2\nexit 1\n'); os.chmod(hook, 0o755)
r1 = card(B, 'capture', stdin='Report while commits fail.')
os.remove(hook); r2 = card(B, 'set', 'E01-S2', 'size=M')
ok('a card whose commit failed goes with the next write',
   r1[0] == 3 and 'NOT committed' in r1[1] and r2[0] == 0 and 'committed + pushed' in r2[1] and on_shared(S, 'Report while commits fail.') and board_true(S)
   and not git(B, 'status', '--porcelain', '--', 'items'), f'{r1}\n{r2}')
ok('a write that was not sent says the card is saved and must not be written again', 'saved here; do NOT run this write again; it is sent with the next card write' in r1[1], r1[1])

B, S = shared(); O = clone(S); refuse(S)
r1 = card(B, 'new', 'E02', stdin=NEWC('mine first')); os.remove(f'{S}/hooks/pre-receive')
r2 = card(O, 'new', 'E02', stdin=NEWC('theirs meanwhile'))
r3 = card(B, 'set', 'E01-S2', 'size=M')
old = new_id(r1[1]); mine = [(i, x) for i, v in cards(B).items() for x in v if 'mine first' in x[1]]
now = mine[0][0] if len(mine) == 1 else None
ok('a renumbered card is said on the line, with both titles and ids, and the card keeps a line saying what it was',
   r1[0] == 3 and r2[0] == 0 and old and old == new_id(r2[1]) and r3[0] == 0 and now and now != old
   and f'Your card "mine first" is now {now}: {old} was taken by "theirs meanwhile" on the shared board' in r3[1]
   and re.search(rf'^- this card was {old} until ', mine[0][1][1], re.M) and on_shared(S, f'this card was {old} until'), f'{r1}\n{r2}\n{r3}\n{mine}')

B, S = shared(); O = clone(S); refuse(S)
r1 = card(B, 'new', 'E02', stdin=NEWC('one two three four five six and ours', 'ours body')); os.remove(f'{S}/hooks/pre-receive')
r2 = card(O, 'new', 'E02', stdin=NEWC('one two three four five six and theirs', 'theirs body'))
r3 = card(B, 'set', 'E01-S2', 'size=M'); ids = [i for i, v in cards(B).items() for _ in v]
ok('two clones file cards with the same first six title words: two files, two ids, both on the shared board',
   r1[0] == 3 and r2[0] == 0 and r3[0] == 0 and 'committed + pushed' in r3[1] and on_shared(S, 'ours body') and on_shared(S, 'theirs body') and len(ids) == len(set(ids)), f'{r1}\n{r2}\n{r3}')

B, S = shared(); O = clone(S); refuse(S)  # both clones write the same lines of one card: this one needs a hand
r1 = card(B, 'append', 'E01-S2', 'Notes', stdin='- ours\n'); os.remove(f'{S}/hooks/pre-receive')
r2 = card(O, 'append', 'E01-S2', 'Notes', stdin='- theirs\n')
r3 = card(B, 'set', 'E01-S3', 'size=M')
ok('stuck (both changed the same lines): nothing written, the reason in plain words and the exact command, no git hint text',
   r1[0] == 3 and r2[0] == 0 and r3[0] == 1 and 'nothing written' in r3[2] and 'both changed' in r3[2] and f'git -C {B} pull --rebase' in r3[2]
   and 'hint:' not in r3[2] and 'Diverging' not in r3[2] and not git(B, 'status', '--porcelain', '--', 'items'), f'{r1}\n{r2}\n{r3}')

B, S = shared(); open(f'{tmp}/deep', 'w', encoding='utf-8').write('[' * 100000); before = set(cards(B))
rc, out, err = card(B, 'capture', f'{tmp}/deep', stdin='Report with a triage output nested too deep.')
ok('triage output nested 100,000 deep: no crash, the report is a card', rc == 0 and len(set(cards(B)) - before) == 1 and 'triage failed: ' in out and 'Traceback' not in err
   and on_shared(S, 'nested too deep.'), f'{rc} {out[:300]} {err[-300:]}')
open(f'{tmp}/good', 'w', encoding='utf-8').write(json.dumps(GOOD))
ok('`triage ok` says when to fall back: if the write says nothing was written', 'if it says nothing was written' in card(B, 'capture', f'{tmp}/good', stdin='x')[1])
for f in ('.claude/commands/dispatch-it.md', '.claude/make-it/sdd/task-reviewer-prompt.md'):
    ok(f'{f} tells a lane what exit 3 means', 'exit 3 means saved here but not sent: do not repeat the write' in re.sub(r'\s+', ' ', open(f'{root}/{f}', encoding='utf-8').read()))

# ---- 4. the skill and its reference --------------------------------------------------------------------------
ref = open(f'{root}/.claude/make-it/references/backlog-board.md', encoding='utf-8').read()
skill = open(f'{root}/.claude/commands/backlog-it.md', encoding='utf-8').read()
flat = lambda s: re.sub(r'\s+', ' ', s)
ok('the reference no longer says a bad triage writes nothing', 'write nothing' not in flat(ref.split('### Card first')[1].split('\n## ')[0]))
ok('the reference sends the triage output through `card.py capture`', 'card.py capture' in ref and 'not sorted yet' in ref and 'triage failed' in ref)
ok('the skill sends the triage output through `card.py capture`', 'card.py capture' in skill and 'not sorted yet' in flat(skill))
ok('the reference and the skill say what a card that was not sent looks like, and that it is relayed', all('NOT sent' in x and 'exit 3' in flat(x).lower() for x in (ref, skill)))
ok('the reference no longer claims every unsent write exits non-zero', 'Any write that didn\'t sync exits non-zero' not in flat(ref))
sys.exit(fail)
PY
echo "PASS: a report always becomes a card, and a card write says truly whether it reached the shared board"
