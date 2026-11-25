#!/usr/bin/env bash
# The three things that make a /backlog-it board SHRINK (E04-S16 tasks 4-6), proven by RUNNING the helpers on
# stand-in boards (scripts/backlog-stand-in/make-board.py) with the stand-in `gh` beside it. No real board, no network.
#   COMBINE   `shrink.py combine` lists candidate groups from facts (same files, same skill, cards that wait on each
#             other) and writes nothing. `bundle` makes one card that lists each original card with ITS OWN check;
#             every helper then counts the bundle as one thing to do and still shows its parts by title with id. A
#             part closes only on its own check; a high-stakes card is never bundled with one that is not; a bundle
#             is at most BUNDLE_MAX cards and one sitting; `unbundle` puts every part back byte for byte.
#   SHIPPED   `sync-prs.py` closes a card whose pull request is merged, whose release carries it and whose release's
#             checks passed: done, `closed_as: shipped-tests-pass`, with a line saying it was not confirmed by a real
#             run and how to reopen. Checks that cannot be read, failed, are still running, or a merge no release
#             carries yet: the card is left and the reason is said. No card is parked at "Live, to check" any more.
#             `reopen` puts a card back in line with the person's words kept; the first screen counts reopened cards.
#   EXPIRY    `shrink.py expire` closes a card nobody asks for after EXPIRE_DAYS quiet days (day 30, not day 29), with
#             a note on why and how to bring it back; `--dry-run` changes nothing. One fixture per reason a card never
#             closes by itself, and each stays open. The first screen counts what will close soon and what did.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 -I - "$root" "$t" <<'PY'
import hashlib, json, os, re, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
BIN, STAND = f'{root}/.claude/make-it/backlog/bin', f'{root}/scripts/backlog-stand-in'
fail = 0
def ok(name, cond, detail=''):
    global fail
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else f'\n     {str(detail)[-1800:]}'))
    fail |= not cond

n = [0]
def board(*args):
    n[0] += 1; d = f'{tmp}/b{n[0]}'
    subprocess.run([sys.executable, f'{STAND}/make-board.py', d, *args], check=True)
    return d
def call(helper, d, *args, stdin=None, board_flag=False):
    env = dict(os.environ, GH_STUB_PRS=f'{d}/prs.json', PATH=STAND + os.pathsep + os.environ['PATH'])
    where = ['--board', f'{d}/board'] if board_flag else [f'{d}/board']
    return subprocess.run([sys.executable, f'{BIN}/{helper}', *where, '--project', 'stand-in', *args], input=stdin, capture_output=True, text=True, encoding='utf-8', env=env)
def run(helper, d, *args, **kw):
    r = call(helper, d, *args, **kw)
    return r.stdout + (f'\n[exit {r.returncode}] {r.stderr}' if r.returncode or r.stderr else '')
shrink = lambda d, *a, stdin=None: call('shrink.py', d, *a, stdin=stdin, board_flag=True)
first = lambda d, *a: run('status.py', d, '--first', '--repo', f'{d}/board', '--lane-cap', '3', *a)
git = lambda d, *a: subprocess.run(['git', '-C', f'{d}/board', *a], capture_output=True, text=True, encoding='utf-8').stdout
state = lambda d: (git(d, 'rev-parse', 'HEAD'), git(d, 'status', '--porcelain'))
def path(d, cid):
    for dp, _, fs in os.walk(f'{d}/board/items'):
        for f in fs:
            p = os.path.join(dp, f)
            if re.search(rf'^id: {cid}$', open(p, encoding='utf-8').read(), re.M): return p
def rd(p): return open(p, encoding='utf-8').read() if os.path.exists(p) else ''
def text(d, cid): return open(p, encoding='utf-8').read() if cid and (p := path(d, cid)) else ''
def fmv(d, cid, k): return (re.search(rf'^{k}:\s*(.*)$', text(d, cid).split('\n---', 1)[0], re.M) or [0, None])[1]
def titles(d):
    out = {}
    for dp, _, fs in os.walk(f'{d}/board/items'):
        for f in fs:
            txt = open(os.path.join(dp, f), encoding='utf-8').read()
            i, ti = re.search(r'^id: (.+)$', txt, re.M), re.search(r'^title: "?(.*?)"?$', txt, re.M)
            if i: out[i.group(1)] = ti.group(1) if ti else ''
    return out
ID = re.compile(r'\bE\d+(?:-S\d+)?\b')
def bare(txt, T):  # every line that holds a card id without that card's title in front of it
    bad = []
    for line in txt.splitlines():
        for m in ID.finditer(line):
            ti = T.get(m.group(0)) or 'Untitled card'; pre = line[:m.start()]
            named = pre.endswith(' (') and line[m.end():m.end() + 1] == ')'; pre = pre[:-2]
            if not (named and (pre.endswith(ti) or (pre.endswith('…') and any(pre[:-1].endswith(ti[:k]) for k in range(8, len(ti)))))): bad.append(line); break
    return bad
QUIET = ['--without', 'waiting,ready-pr,stalled-pr,growing', '--plan', 'none', '--groom-days', '1']  # a calm board: the next thing is the next safe card
src = lambda f: open(f'{BIN}/{f}', encoding='utf-8').read() if os.path.exists(f'{BIN}/{f}') else ''

# ============================== COMBINE ==============================
d = board(*QUIET, '--with', 'bundle-set'); T = titles(d); before = state(d)
out = run('shrink.py', d, 'combine', board_flag=True)
grp = lambda *ids: any(all(f'({i})' in g for i in ids) for g in re.split(r'\n(?=  \d+\. )', out))  # one numbered group holds all of them
ok('combine: cards that name the same files are one group, with the files as the evidence',
   re.search(r'Same file\n(?:.*\n)*?  \d+\. src/csv\.py, src/export\.py -- 2 cards', out) is not None and 'The export file has no header (E01-S60)' in out and 'The export total is off by one (E01-S61)' in out, out)
ok('combine: a file named only in a card\'s text still groups it, and the helper says where the fact came from',
   re.search(r'  \d+\. src/export\.py -- 3 cards', out) is not None and re.search(r'Export times out on big accounts \(E01-S62\).*named in its text', out) is not None, out)
ok('combine: cards of one skill (category) are a group', re.search(r'Same skill\n(?:.*\n)*?  \d+\. export -- 3 cards', out) is not None, out)
ok('combine: cards that already wait on each other are a group', re.search(r'Wait on each other\n(?:.*\n)*?\s+Sort the report by date \(E02-S20\).* waits on Add a date column to the report \(E02-S21\)', out) is not None, out)
ok('combine: a high-stakes card is never grouped with a card that is not, and the helper says so',
   not grp('E02-S22', 'E02-S23') and re.search(r'The sign-in page remembers the last user \(E02-S23\).*high-stakes', out) is not None, out)
ok('combine: every card is named by its title with its id', '[exit' not in out and not bare(out, T), bare(out, T) or out)
ok('combine: it only proposes -- nothing on the board changes', state(d) == before, state(d))
ok('combine <card id>: only the groups that card is in (for the offer at capture)', (o := run('shrink.py', d, 'combine', 'E01-S62', board_flag=True)) and 'E01-S62' in o and 'E02-S20' not in o, o)

CHECKS = 'E01-S61: the export of a 3-row file totals 3\nE01-S60: the first line of the export file is the header\n'
ASK = 'title: Two export fixes in one sitting\nground: same file\nwhy: both change the writer in src/export.py and src/csv.py\n'
refused = []
for name, ids, stdin, says in (
    ('a high-stakes card with one that is not', ['E02-S22', 'E02-S23'], 'title: x\nground: same file\nwhy: same file\nE02-S22: a\nE02-S23: b\n', 'high-stakes'),
    ('more cards than BUNDLE_MAX', ['E01-S60', 'E01-S61', 'E02-S20', 'E02-S21', 'E02-S22', 'E01-S10'], 'title: x\nground: same goal\nwhy: y\n' + ''.join(f'{i}: c\n' for i in ('E01-S60', 'E01-S61', 'E02-S20', 'E02-S21', 'E02-S22', 'E01-S10')), 'at most 5'),
    ('more than one sitting', ['E01-S60', 'E01-S61', 'E01-S62'], ASK + CHECKS + 'E01-S62: big accounts export in under a minute\n', 'one sitting'),
    ('a card with no check of its own', ['E01-S60', 'E01-S61'], ASK + 'E01-S61: totals 3\n', 'its own check'),
    ('no ground', ['E01-S60', 'E01-S61'], 'title: x\nwhy: y\n' + CHECKS, 'same file, same root cause, or same goal'),
    ('no reason', ['E01-S60', 'E01-S61'], 'title: x\nground: same file\n' + CHECKS, 'why'),
    ('a single card', ['E01-S60'], ASK + CHECKS, 'at least 2'),
    ('a card that is finished', ['E01-S60', 'E01-S30'], ASK + CHECKS + 'E01-S30: z\n', 'done')):
    r = shrink(d, 'bundle', *ids, stdin=stdin)
    good = r.returncode != 0 and says in r.stderr and state(d) == before
    ok(f'bundle refuses {name}, says why, and writes nothing', good, r.stdout + r.stderr)
h = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest() if p else ''
m60, m61 = path(d, 'E01-S60'), path(d, 'E01-S61'); was = {m60: (h(m60), open(m60, encoding='utf-8').read()), m61: (h(m61), open(m61, encoding='utf-8').read())}
st0 = run('status.py', d); open0 = int((re.search(r'(\d+) open', st0) or [0, -1])[1])
r = shrink(d, 'bundle', 'E01-S60', 'E01-S61', stdin=ASK + CHECKS)
bid = (re.search(r'^new: Two export fixes in one sitting \((E\d+-S\d+)\)', r.stdout) or [0, ''])[1]
ok('bundle: one new card, said with its parts by title with id', r.returncode == 0 and bool(bid) and 'The export file has no header (E01-S60)' in r.stdout and 'The export total is off by one (E01-S61)' in r.stdout, r.stdout + r.stderr)
bt = text(d, bid) if bid else ''
ok('the bundle card lists each original card with ITS OWN check, and says the ground and the reason',
   re.search(r'^- \[ \] The export file has no header \(E01-S60\) -- check: the first line of the export file is the header$', bt, re.M) is not None
   and re.search(r'^- \[ \] The export total is off by one \(E01-S61\) -- check: the export of a 3-row file totals 3$', bt, re.M) is not None
   and 'ground: same file' in bt and 'both change the writer' in bt, bt)
ok('the bundle takes the highest priority of its parts, and stays a bug when a part is one', fmv(d, bid, 'priority') == 'P1' and fmv(d, bid, 'type') == 'breakfix' and fmv(d, bid, 'bundles') == '[E01-S60, E01-S61]', bt)
ok('each original card is kept whole and only marked as part of the bundle (one new line, nothing else)',
   all(open(p, encoding='utf-8').read() == txt.replace('\n---\n', f'\nbundledIn: {bid}\n---\n', 1) for p, (_, txt) in was.items()), text(d, 'E01-S60'))
T = titles(d)
st = run('status.py', d)
ok('status counts the bundle as ONE thing to do: the open cards are the same, the things to do are one fewer',
   re.search(rf'{open0} open, .*· {open0 - 1} things to do \(1 bundle holds 2 cards\)', st) is not None, st[:400])
ok('status shows the bundle with its parts by title with id, and never offers a part to start on its own',
   re.search(r'BUNDLES\n  Two export fixes in one sitting \(' + bid + r'\) · same file · 2 of 2 parts open\n\s+The export file has no header \(E01-S60\)', st) is not None
   and 'The export total is off by one (E01-S61)' not in st.split('UP NEXT')[1].split('BURN-DOWN')[0] and not bare(st, T), bare(st, T) or st)
b = rd(f'{d}/board/BOARD.md')
ok('BOARD.md: Next up is the bundle, not a part; the bundle line lists its parts; a part is marked',
   f"**Next up:** {bid.split('-')[1]}\n" in b and re.search(rf'^- .*{bid} · "?Two export fixes in one sitting.*bundle of 2', b, re.M) is not None
   and re.search(r'^  - part: The export total is off by one \(E01-S61\)', b, re.M) is not None and re.search(rf'^- .*E01-S61 · .*in bundle {bid}', b, re.M) is not None, b)
sc = subprocess.run([sys.executable, f'{BIN}/scope.py', f'{d}/board'], capture_output=True, text=True, encoding='utf-8')
sj = json.loads(sc.stdout) if sc.returncode == 0 else {}
ok('scope.py (what plan and groom cover): the bundle is in scope, its parts are not, and the parts are listed with it by title',
   bid in sj.get('scope', []) and not {'E01-S60', 'E01-S61'} & set(sj.get('scope', [])) and any(x.get('id') == bid and [p.get('title') for p in x.get('parts', [])] == ['The export file has no header', 'The export total is off by one'] for x in sj.get('bundles', [])), sc.stdout[-600:] + sc.stderr)
fs = first(d)
ok('the first screen: the next thing is the bundle, one thing, with its parts by title with id under it',
   'Two export fixes in one sitting (' + bid + ')' in fs.split('NEEDS YOU')[0] and re.search(r'part: The export file has no header \(E01-S60\)', fs.split('NEEDS YOU')[0]) is not None
   and re.search(r'part: The export total is off by one \(E01-S61\)', fs.split('NEEDS YOU')[0]) is not None and not bare(fs, T) and len(fs.splitlines()) <= 25 and max(map(len, fs.splitlines())) <= 110, bare(fs, T) or fs)
# --- a part closes only on its own check ---
r = call('card.py', d, 'set', 'E01-S60', 'status=done', board_flag=True)
ok('a part cannot be closed by a plain write: only its own check closes it', r.returncode != 0 and 'own check' in r.stderr and fmv(d, 'E01-S60', 'status') == 'backlog', r.stdout + r.stderr)
r = call('card.py', d, 'set', bid, 'status=done', board_flag=True)
ok('the bundle cannot close while a part is open, and the refusal names the parts', r.returncode != 0 and 'The export file has no header (E01-S60)' in r.stderr and fmv(d, bid, 'status') == 'backlog', r.stdout + r.stderr)
r = shrink(d, 'part-done', 'E01-S60', stdin='ran the export: line 1 is "name,total"\n')
ok('part-done: that card closes on its own check, with what showed it; the other part stays open',
   r.returncode == 0 and fmv(d, 'E01-S60', 'status') == 'done' and 'line 1 is "name,total"' in text(d, 'E01-S60') and fmv(d, 'E01-S61', 'status') == 'backlog'
   and re.search(r'^- \[x\] The export file has no header \(E01-S60\)', text(d, bid), re.M) is not None and '1 of 2' in r.stdout, r.stdout + r.stderr)
ok('part-done refuses a card that is in no bundle', shrink(d, 'part-done', 'E01-S10', stdin='x\n').returncode != 0)
# --- a bundle's pull request is merged and released: it still waits for each part's own check ---
d2 = board(*QUIET, '--with', 'bundle-set,shipped')
r = shrink(d2, 'bundle', 'E01-S60', 'E01-S61', stdin=ASK + CHECKS); b2 = (re.search(r'\((E\d+-S\d+)\)', r.stdout) or [0, ''])[1]
call('card.py', d2, 'set', b2, 'status=in-progress', 'stage=Fix ready', 'pr=[21]', board_flag=True)
o = run('sync-prs.py', d2, '--repo', f'{d2}/board')
ok('a released bundle is not closed while a part has not passed its own check; the parts are named', fmv(d2, b2, 'status') == 'in-progress' and re.search(r'2 of its parts have not passed their own check: .*\(E01-S60\).*\(E01-S61\)', o) is not None, o)
shrink(d2, 'part-done', 'E01-S60', stdin='seen\n'); r = shrink(d2, 'part-done', 'E01-S61', stdin='seen\n')
o = run('sync-prs.py', d2, '--repo', f'{d2}/board')
ok('once every part has passed its own check, the released bundle closes', 'every part' in r.stdout and fmv(d2, b2, 'status') == 'done' and fmv(d2, b2, 'closed_as') == 'shipped-tests-pass', r.stdout + o)
# --- un-bundling is one command and loses nothing ---
d3 = board(*QUIET, '--with', 'bundle-set'); ps = [path(d3, i) for i in ('E01-S60', 'E01-S61', 'E02-S22')]; hs = [h(p) for p in ps]
r = shrink(d3, 'bundle', 'E01-S60', 'E01-S61', 'E02-S22', stdin='title: Three in one\nground: same goal\nwhy: one release note\n' + CHECKS + 'E02-S22: the page reads well\n')
b3 = (re.search(r'\((E\d+-S\d+)\)', r.stdout) or [0, ''])[1]
r1 = shrink(d3, 'unbundle', 'E02-S22')
ok('unbundle <a part>: that card is back as it was, byte for byte, and the bundle keeps the rest',
   r1.returncode == 0 and h(ps[2]) == hs[2] and fmv(d3, b3, 'bundles') == '[E01-S60, E01-S61]' and fmv(d3, 'E01-S60', 'bundledIn') == b3 and 'Tidy the words on the sign-in page (E02-S22)' in r1.stdout, r1.stdout + r1.stderr)
r2 = shrink(d3, 'unbundle', b3)
ok('unbundle <the bundle>: every part is back as it was, byte for byte', r2.returncode == 0 and [h(p) for p in ps] == hs, r2.stdout + r2.stderr)
ok('the bundle card is kept, closed as un-bundled (never deleted), and the parts are back in line',
   bool(b3) and fmv(d3, b3, 'status') == 'done' and fmv(d3, b3, 'closed_as') == 'unbundled' and '**Next up:** S61\n' in rd(f'{d3}/board/BOARD.md'), r2.stdout)
s = src('shrink.py')
ok('the limits are named constants, each with its reason', all(re.search(rf'^{k} = .+#.{{30,}}', s, re.M) for k in ('BUNDLE_MAX', 'SITTING')), 'missing')

# ============================== SHIPPED MEANS DONE ==============================
d = board(*QUIET, '--with', 'shipped'); T = titles(d); before = state(d)
dry = run('sync-prs.py', d, '--repo', f'{d}/board', '--dry-run')
ok('reconcile --prs --dry-run says what would close and changes nothing', 'Dates show in the wrong time zone (E01-S70)' in dry and 'dry run' in dry and state(d) == before, dry)
o = run('sync-prs.py', d, '--repo', f'{d}/board'); c70 = text(d, 'E01-S70')
ok('merged, carried by the newest release, the release\'s checks passed -> done, closed as shipped-tests-pass',
   fmv(d, 'E01-S70', 'status') == 'done' and fmv(d, 'E01-S70', 'closed_as') == 'shipped-tests-pass' and re.search(r'\(E01-S70\) · .*#21 merged .*v1\.2\.0.*checks passed', o) is not None, o)
ok('the closed card says what proved it, that no real run confirmed it, and how to reopen it',
   '## Shipped means done' in c70 and 'v1.2.0' in c70 and 'not confirmed by a real run' in c70 and '/backlog-it reopen E01-S70' in c70, c70)
ok('a card left at the old Live stage is closed by the same rule (the "live, to check" pile is swept)', fmv(d, 'E01-S74', 'status') == 'done' and fmv(d, 'E01-S74', 'closed_as') == 'shipped-tests-pass', o)
ok('a fix whose own pull request was closed and carried by a merged release pull request closes too', fmv(d, 'E01-S75', 'status') == 'done', o)
ok('merged after the newest release: left, and said', fmv(d, 'E01-S72', 'status') == 'in-progress' and re.search(r'The invoice email has no subject \(E01-S72\) · .*not in a release yet', o) is not None, o)
ok('a pull request still open: left, and said', fmv(d, 'E01-S76', 'status') == 'in-progress' and re.search(r'\(E01-S76\) · #26 open', o) is not None, o)
ok('reconcile --prs: every card by its title with its id', '[exit' not in o and not bare(o, T), bare(o, T) or o)
ok('no card is moved to a Live stage, and the board has no "Live, to check" line',
   not any(fmv(d, i, 'stage') == 'Live' and fmv(d, i, 'status') != 'done' for i in T if '-S' in i) and 'Live, to check' not in rd(f'{d}/board/BOARD.md') and 'Live' not in run('status.py', d), run('status.py', d))
for kind, says in (('checks-unreadable', 'could not be read'), ('checks-fail', '1 of its 2 checks failed (unit tests)'), ('checks-running', 'still running'), ('no-checks', 'no checks')):
    dk = board(*QUIET, '--with', f'shipped,{kind}'); o = run('sync-prs.py', dk, '--repo', f'{dk}/board')
    ok(f'{kind}: the card is left as it was, and the reason is said ("{says}")', fmv(dk, 'E01-S70', 'status') == 'in-progress' and fmv(dk, 'E01-S70', 'closed_as') is None
       and re.search(r'Dates show in the wrong time zone \(E01-S70\) · .*' + re.escape(says), o) is not None and '[exit' not in o, o)
dk = board(*QUIET, '--with', 'shipped,no-tags'); o = run('sync-prs.py', dk, '--repo', f'{dk}/board')
ok('a repo with no release at all: the merge is the release, and its own checks decide', fmv(dk, 'E01-S70', 'status') == 'done' and fmv(dk, 'E01-S72', 'status') == 'done', o)
o = run('sync-prs.py', d)
ok('with no --repo nothing closes on a guess', 'skipped' in o and fmv(d, 'E01-S72', 'status') == 'in-progress', o)
old = board(*QUIET, '--with', 'shipped'); st = run('status.py', old); bd = subprocess.run([sys.executable, f'{BIN}/regen-board.py', f'{old}/board', '--project', 'stand-in'], capture_output=True, text=True)
ok('before any sync, an old Live card shows under Shipping (waiting for its release), not in a pile of its own',
   re.search(r'\*\*Shipping:\*\* .*S74', rd(f'{old}/board/BOARD.md')) is not None and 'Live' not in st and 'A fix merged long ago that nobody checked (E01-S74)' in st, st)
# --- reopen ---
WORDS = 'Opened the report at 9pm: the date still shows yesterday.\n50% of rows, $HOME and `x` -- é\n'
r = shrink(d, 'reopen', 'E01-S70', stdin=WORDS); c = text(d, 'E01-S70')
ok('reopen: the card is back in line (a bug at Reported), no longer closed, with the date it came back',
   r.returncode == 0 and fmv(d, 'E01-S70', 'status') == 'backlog' and fmv(d, 'E01-S70', 'stage') == 'Reported' and fmv(d, 'E01-S70', 'closed_as') is None and re.fullmatch(r'\d{4}-\d\d-\d\d', fmv(d, 'E01-S70', 'reopened') or '') is not None
   and 'Dates show in the wrong time zone (E01-S70)' in r.stdout, r.stdout + r.stderr)
ok('reopen keeps the person\'s words, line for line', all(f'> {l}' in c for l in WORDS.strip().split('\n')) and '## Reopened' in c, c)
ok('reopen keeps the history: the old close note stays, and the old pull request is named in the note, not in pr:', '## Shipped means done' in c and fmv(d, 'E01-S70', 'pr') is None and '21' in c.split('## Reopened')[1], c)
o = run('sync-prs.py', d, '--repo', f'{d}/board')
ok('a reopened card is not closed again by its old pull request', fmv(d, 'E01-S70', 'status') == 'backlog', o)
fs = first(d)
ok('the first screen counts reopened cards, by title with id', re.search(r'Reopened: 1 fix did not hold -- Dates show in the wrong time zone \(E01-S70\)', fs) is not None and len(fs.splitlines()) <= 25 and max(map(len, fs.splitlines())) <= 110, fs)
r = shrink(d, 'reopen', 'E01-S76', stdin='x\n')
ok('reopen refuses a card that is not closed', r.returncode != 0 and 'not closed' in r.stderr, r.stdout + r.stderr)

# ============================== EXPIRY ==============================
d = board(*QUIET, '--with', 'quiet'); T = titles(d); before = state(d)
KEEP = {'E02-S31': 'day 29', 'E01-S80': 'a bug', 'E02-S33': 'high-stakes', 'E02-S34': 'a safety word in its title', 'E02-S35': 'the owner captured it', 'E02-S36': 'it does not say where it came from',
        'E02-S37': 'pinned', 'E02-S38': 'another open card waits on it', 'E02-S39': 'a person is named on it', 'E02-S40': 'another card mentioned it lately', 'E02-S42': 'it has a pull request',
        'E02-S43': 'somebody started it', 'E02-S44': 'in a bundle whose other part is alive', 'E02-S45': 'in a bundle whose other part is alive', 'E02-S46': 'a bundle with open parts',
        'E02-S47': 'a person brought it back', 'E02-S48': 'its type is not recorded'}
dry = run('shrink.py', d, 'expire', '--dry-run', board_flag=True)
ok('expire --dry-run lists what would close and why, and changes nothing',
   re.search(r'Would close 1 card.*\n\s+A tidy-up nobody asked for \(E02-S30\) · quiet 30 days', dry) is not None and state(d) == before, dry)
ok('expire --dry-run: a card one day short is not closed, and is listed as closing soon', re.search(r'Another tidy-up nobody asked for \(E02-S31\) · quiet 29 days, closes in 1 day', dry) is not None, dry)
ok('expire --dry-run says why the others are kept, as counts by reason, with no bare id', 'Kept' in dry and 'a bug' in dry and 'high-stakes' in dry and not bare(dry, T) and '[exit' not in dry, bare(dry, T) or dry)
fs = first(d)
ok('the first screen offers the count of quiet cards about to close, and how to see them',
   re.search(r'Quiet cards: 2 will close in the next 7 days .*expire --dry-run', fs) is not None and len(fs.splitlines()) <= 25 and max(map(len, fs.splitlines())) <= 110, fs)
first(d, '--seen')
r = shrink(d, 'expire'); c = text(d, 'E02-S30')
ok('expire closes the plain quiet card on day 30: done, closed as expired', r.returncode == 0 and fmv(d, 'E02-S30', 'status') == 'done' and fmv(d, 'E02-S30', 'closed_as') == 'expired' and 'A tidy-up nobody asked for (E02-S30)' in r.stdout, r.stdout + r.stderr)
ok('the closed card says why it closed and how to bring it back, and nothing was deleted', '## Expired' in c and 'quiet for 30 days' in c and '/backlog-it reopen E02-S30' in c and '## Found' in c, c)
for i, why in KEEP.items():
    ok(f'never closes by itself: {why} ({T[i]})', fmv(d, i, 'status') != 'done', text(d, i))
ok('nothing else on the board closed', sum(fmv(d, i, 'closed_as') == 'expired' for i in T) == 1)
fs = first(d)
ok('the first screen says how many closed this way since the last look', re.search(r'Shipped: .*· 1 expired', fs) is not None and len(fs.splitlines()) <= 25 and max(map(len, fs.splitlines())) <= 110, fs)
ok('running it again closes nothing more', 'Closed 0' in shrink(d, 'expire').stdout)
r = shrink(d, 'reopen', 'E02-S30', stdin='I do want this page tidied.\n')
dry = run('shrink.py', d, 'expire', '--dry-run', board_flag=True)
ok('an expired card comes back with one command, and a card a person brought back never expires again',
   r.returncode == 0 and fmv(d, 'E02-S30', 'status') == 'backlog' and fmv(d, 'E02-S30', 'closed_as') is None and '> I do want this page tidied.' in text(d, 'E02-S30') and '## Expired' in text(d, 'E02-S30') and 'a person brought it back' in dry, dry)
s = src('status.py')
ok('the 30 days and the 7 days\' notice are named constants, each with its reason, and so is the list of safety words',
   all(re.search(rf'^{k} = .+#.{{30,}}', s, re.M) for k in ('EXPIRE_DAYS', 'EXPIRE_WARN', 'SAFETY')) and re.search(r'^EXPIRE_DAYS = 30\b', s, re.M) is not None, 'missing')

# ============================== the skill and its reference ==============================
flat = lambda p: re.sub(r'\s+', ' ', open(f'{root}/{p}', encoding='utf-8').read())
cmd, ref = flat('.claude/commands/backlog-it.md'), flat('.claude/make-it/references/backlog-board.md')
ok('the skill routes combine, unbundle, reopen and expire', all(f'| `{k}' in cmd for k in ('combine [filter]', 'unbundle <id>', 'reopen <id> <what was seen>', 'expire [--dry-run]')), '')
ok('the skill: groom runs combine and expire; capture offers a bundle when the new card clearly belongs with an open one',
   'shrink.py' in cmd and re.search(r'groom[^|]*combine', cmd) is not None and re.search(r'[Cc]apture[^#]*combine <the new id>', cmd) is not None, '')
ok('the reference: a bundle proposal is one multi-select, one option per bundle (which cards, the ground, the evidence), no "all of them"; nothing combines without the pick',
   '### `combine [filter]`' in ref and 'one option per proposed bundle' in ref and 'no "all of them"' in ref and 'Nothing combines without' in ref, '')
ok('the reference names the three grounds and says who judges the last two', all(x in ref for x in ('**Same file**', '**Same root cause**', '**Same goal**')) and 'its reason is written' in ref, '')
ok('the reference defines ONE place a card lists the files it would change, and who fills it', 'files: [src/export.py, src/csv.py]' in ref and all(x in ref for x in ('`plan` writes it', 'grounder', 'A lane')), '')
ok('the reference: the bug line ends at released with passing tests; no stage parks a card to be checked',
   '**Reported → Cause found → Fix ready → done**' in ref and 'shipped-tests-pass' in ref and '| Live |' not in ref and '| Checked |' not in ref and '**Live, to check**' not in ref, '')
ok('the reference: expiry is written as a rule, with what never expires', '### `expire [--dry-run]`' in ref and all(x in ref for x in ('30 quiet days', 'Never expires', '`## Captured`', '`## Found`', 'closed_as: expired', 'when it cannot be told')), '')
for f in ('.claude/commands/resume-it.md', '.claude/commands/wrap-it.md', '.claude/commands/clear-it.md', '.claude/make-it/references/ship-it-guide.md', '.claude/make-it/confluence-docs/16-backlog-it.md', '.claude/commands/make-it.md'):
    x = flat(f)
    ok(f'{f} no longer parks cards at Live or Checked', 'Live, to check' not in x and 'stage: Live' not in x and 'to `Live`' not in x and 'Live and Checked' not in x and '→ Live → Checked' not in x, '')
for hname in ('shrink.py', 'status.py', 'regen-board.py', 'sync-prs.py', 'scope.py', 'check-plan.py', 'card.py'):
    r = subprocess.run([sys.executable, f'{BIN}/{hname}', '--self-test'], capture_output=True, text=True, encoding='utf-8')
    ok(f'{hname} --self-test passes', r.returncode == 0, r.stderr[-600:])
sys.exit(fail)
PY
