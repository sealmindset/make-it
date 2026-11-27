#!/usr/bin/env bash
# Two things /backlog-it does without anyone remembering (E04-S16 tasks 7 and 11), proven by RUNNING the helpers on
# stand-in boards (scripts/backlog-stand-in/make-board.py) with the stand-in `gh` beside it. No real board, no network.
#   SITTING  `sitting.py pick` brings the held high-stakes cards for the weekly sitting by a written rule: the one
#            that frees the most other cards first, then the higher priority, then the older card; a bundle counts
#            once; at most SIT[1]. `answer` writes the owner's pick on the card (`## Answers`, `decision:` and
#            `answers:` cleared) and the card is not brought again unless it changes; `not-now` is kept and the card
#            stays out for SIT_REST days unless it changes. A sitting is due when a card can be brought and none is
#            on record in the last SIT_EVERY days; the first screen then says so in one line, with one choice.
#   SORT     `sync-prs.py --sort` puts every open pull request into exactly one of six groups from facts (`gh`, and
#            the card's `reviewed:` line): READY, OUT OF DATE, CAN BE SETTLED, STALLED, NEEDS YOU, WILL NEVER MERGE.
#            Each line names the pull request by its title and number and says the action. A pull request that is
#            simply moving is counted, not sorted. When the facts cannot be read it says so and sorts nothing.
#            `reconcile --prs` (a plain `sync-prs.py` run) ends with the sort, and the first screen counts each group.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 -I - "$root" "$t" <<'PY'
import datetime, json, os, re, subprocess, sys
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
def call(helper, d, *args, stdin=None, board_flag=False, prs=None):
    env = dict(os.environ, GH_STUB_PRS=prs or f'{d}/prs.json', PATH=STAND + os.pathsep + os.environ['PATH'])
    where = ['--board', f'{d}/board'] if board_flag else [f'{d}/board']
    if not os.path.exists(f'{BIN}/{helper}'): return subprocess.CompletedProcess([], 127, '', f'no {helper}')
    return subprocess.run([sys.executable, f'{BIN}/{helper}', *where, '--project', 'stand-in', *args], input=stdin, capture_output=True, text=True, encoding='utf-8', env=env)
def run(helper, d, *args, **kw):
    r = call(helper, d, *args, **kw)
    return r.stdout + (f'\n[exit {r.returncode}] {r.stderr}' if r.returncode or r.stderr else '')
sit = lambda d, *a, stdin=None: call('sitting.py', d, *a, stdin=stdin, board_flag=True)
sits = lambda d, *a, stdin=None: (lambda r: r.stdout + (f'\n[exit {r.returncode}] {r.stderr}' if r.returncode or r.stderr else ''))(sit(d, *a, stdin=stdin))
first = lambda d, *a: run('status.py', d, '--first', '--repo', f'{d}/board', '--lane-cap', '3', *a)
git = lambda d, *a: subprocess.run(['git', '-C', f'{d}/board', *a], capture_output=True, text=True, encoding='utf-8').stdout
state = lambda d: (git(d, 'rev-parse', 'HEAD'), git(d, 'status', '--porcelain'))
def path(d, cid):
    for dp, _, fs in os.walk(f'{d}/board/items'):
        for f in fs:
            p = os.path.join(dp, f)
            if re.search(rf'^id: {cid}$', open(p, encoding='utf-8').read(), re.M): return p
def text(d, cid): return open(path(d, cid), encoding='utf-8').read()
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
def add(d, cid, title, **kv):  # one more card on the stand-in board, written as a lane would leave it
    e = 'EPIC-02-board-work' if cid.startswith('E02') else 'EPIC-01-bugs'
    kv = {'id': cid, 'title': f'"{title}"', 'type': 'story', 'status': 'backlog', 'priority': 'P2', 'created': str(TODAY), 'updated': str(TODAY), **kv}
    open(f"{d}/board/items/{e}/stories/{cid.split('-')[1]}.md", 'w', encoding='utf-8').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n\n## Goal\nx\n')
TODAY = datetime.date.today(); day = lambda k: str(TODAY + datetime.timedelta(days=k))
src = lambda f: open(f'{BIN}/{f}', encoding='utf-8').read() if os.path.exists(f'{BIN}/{f}') else ''
picks = lambda out: re.findall(r'^\d\. (.*?) · ', out, re.M)
QUIET = ['--without', 'waiting,ready-pr,stalled-pr,growing', '--plan', 'none', '--groom-days', '1']

# ============================== THE WEEKLY SITTING ==============================
d = board(); T = titles(d); before = state(d)
out = sits(d, 'pick')
ok('pick: the held cards, the ones that free the most other cards first, then the higher priority, then the older card',
   picks(out) == ['Move sign-in to the new provider (E02-S1)', 'Change the billing tables (E02-S2)', 'Delete the old audit data (E02-S3)', 'Send the monthly statement to every customer (E02-S4)'], out)
ok('pick: each card says how many other cards it frees, and names them by title with id',
   re.search(r'1\. Move sign-in to the new provider \(E02-S1\) · P1 · open 30 days\n   frees 3 other cards: .*The sign-in page uses the new provider \(E02-S5\)', out) is not None
   and '   frees no other card: nothing else waits on it' in out and not bare(out, T), bare(out, T) or out)
ok('pick: the rule is said on the screen, and where each card is', 'The rule: the card that frees the most other cards first, then the higher priority, then the older card; a bundle counts once; at most 5.' in out
   and f'   the card: {path(d, "E02-S1")}' in out, out)
ok('pick and due write nothing', '[exit' not in out and '[exit' not in sits(d, 'due') and state(d) == before, state(d))
ok('due: no sitting is on record and held cards wait -> a sitting is due', sits(d, 'due').startswith('A weekly sitting is due: 4 held cards can be brought, and no sitting is on record.'), sits(d, 'due'))

add(d, 'E02-S60', 'Rotate every sign-in secret', priority='P1', stakes='critical')
add(d, 'E02-S61', 'Move the invoices to a new table', priority='P3', stakes='critical')
add(d, 'E02-S62', 'Send a notice to every customer', priority='P3', stakes='critical', created=day(-50))
add(d, 'E02-S70', 'Two sign-in changes in one sitting', bundles='[E02-S71, E02-S72]')
add(d, 'E02-S71', 'Change who may reset a password', stakes='critical', bundledIn='E02-S70')
add(d, 'E02-S72', 'Change how long a session lasts', stakes='critical', bundledIn='E02-S70')
out = sits(d, 'pick')
ok('pick: at most five, in the rule\'s order (a new P1 goes ahead of older P2 cards; nothing is freed by either)',
   picks(out) == ['Move sign-in to the new provider (E02-S1)', 'Change the billing tables (E02-S2)', 'Rotate every sign-in secret (E02-S60)', 'Delete the old audit data (E02-S3)', 'Send the monthly statement to every customer (E02-S4)'], out)
ok('pick: the rest are counted for a later sitting, never listed', '8 held high-stakes cards, 5 brought to this sitting' in out and '3 more held cards wait for a later sitting' in out, out)
for c in ('E02-S1', 'E02-S2', 'E02-S60', 'E02-S3', 'E02-S4', 'E02-S62'): sit(d, 'not-now', c)
out = sits(d, 'pick')
ok('pick: a bundle counts once -- the bundle is brought, its parts are not',
   picks(out) == ['Two sign-in changes in one sitting (E02-S70)', 'Move the invoices to a new table (E02-S61)'] and 'Change who may reset a password' not in out, out)
ask = lambda d, cid, q, a: subprocess.run([sys.executable, f'{BIN}/card.py', '--board', f'{d}/board', 'set', cid, f'decision={q}', f'answers={a}'], capture_output=True, text=True)  # the skill writes the question as asked
ask(d, 'E02-S70', 'Both sign-in changes touch every account. Rehearse them first, or change them now?', 'Rehearse first -- both run on the staging copy first | Change now -- both go live today | Not now -- stays on the board')
r = sit(d, 'answer', 'E02-S70', 'Rehearse first', stdin='both changes run on the staging copy before anything live changes\n')
ok('a bundle that was brought can be answered, and its answer is on the bundle card', r.returncode == 0 and '**Rehearse first**' in text(d, 'E02-S70')
   and picks(sits(d, 'pick')) == ['Move the invoices to a new table (E02-S61)'], r.stdout + r.stderr)

# --- an answer is written on the card, and the card is not brought again unless it changes ---
d = board(); T = titles(d)
r = subprocess.run([sys.executable, f'{BIN}/card.py', '--board', f'{d}/board', 'set', 'E02-S2', 'decision=The billing tables hold live invoices. Change them now, or after month end?', 'answers=Now -- rehearse on a copy first | After month end -- waits two weeks'], capture_output=True, text=True)
before = (state(d), text(d, 'E02-S1'))
r = sit(d, 'answer', 'E02-S1', 'Add alongside', stdin='x\n')
ok('answer: a card with no answers of its own is refused in plain words, nothing written', r.returncode not in (0, 3) and 'has no answers of its own' in r.stderr and (state(d), text(d, 'E02-S1')) == before, r.stdout + r.stderr)
ask(d, 'E02-S1', 'Every sign-in moves to the new provider. Run it beside the old one, or switch over?', 'Add alongside -- the new one runs beside the old | Switch over -- the old one stops | Not now -- stays on the board')
before = (state(d), text(d, 'E02-S1'))
r = sit(d, 'answer', 'E02-S1', 'Yes', stdin='x\n')
ok('answer: a pick that is not one of the card\'s own answers (a plain "Yes") is refused, naming the answers it has; nothing written', r.returncode not in (0, 3)
   and '"Yes" is not one of its answers (Add alongside, Switch over, Not now)' in r.stderr and (state(d), text(d, 'E02-S1')) == before, r.stdout + r.stderr)
r = sit(d, 'answer', 'E02-S1', 'Add alongside', stdin='the new provider runs beside the old one; rehearse on the staging copy first\n')
c = text(d, 'E02-S1') if r.returncode == 0 else ''
ok('answer: the pick is written under ## Answers with the date, the answer by name and what it does',
   r.returncode == 0 and re.search(rf'## Answers\n- {TODAY} weekly sitting -- \*\*Add alongside\*\*: the new provider runs beside the old one; rehearse on the staging copy first', c) is not None, r.stdout + r.stderr + c)
ok('answer: the line printed names the card by title with id and says what happened to the write',
   r.stdout.startswith('Move sign-in to the new provider (E02-S1): answer recorded at the weekly sitting ("Add alongside") · committed here'), r.stdout + r.stderr)
ok('answer: the board commit holds it, and nothing is left unsaved', 'weekly sitting, answered' in git(d, 'log', '-1', '--format=%s') and git(d, 'status', '--porcelain') == '', git(d, 'log', '-1', '--format=%s') + git(d, 'status', '--porcelain'))
r = sit(d, 'answer', 'E02-S2', 'After month end', stdin='waits two weeks; nothing changes until then\n')
ok('answer: a question that was on the card is cleared with it (`decision:` and `answers:`)', r.returncode == 0 and fmv(d, 'E02-S2', 'decision') is None and fmv(d, 'E02-S2', 'answers') is None
   and '**After month end**' in text(d, 'E02-S2'), r.stdout + r.stderr)
out = sits(d, 'pick')
ok('an answered card is not brought again', picks(out) == ['Delete the old audit data (E02-S3)', 'Send the monthly statement to every customer (E02-S4)'] and 'Left out: 2 already answered at a sitting' in out, out)
ok('after a sitting none is due for seven days: day 6 no, day 7 yes', sits(d, 'due').startswith('No sitting is due: the last was today')
   and sits(d, 'due', '--as-of', day(6)).startswith('No sitting is due: the last was 6 days ago') and sits(d, 'due', '--as-of', day(7)).startswith('A weekly sitting is due: 2 held cards can be brought, and the last sitting was 7 days ago'), sits(d, 'due', '--as-of', day(7)))
subprocess.run([sys.executable, f'{BIN}/card.py', '--board', f'{d}/board', 'append', 'E02-S1', 'Notes'], input='- the staging copy is gone; this needs a new place to rehearse\n', capture_output=True, text=True)
ok('an answered card that changes is brought again', 'Move sign-in to the new provider (E02-S1)' in picks(sits(d, 'pick')), sits(d, 'pick'))

r = sit(d, 'not-now', 'E02-S3'); c = text(d, 'E02-S3')
ok('not now: kept on the card, with the day it comes back', r.returncode == 0 and re.search(rf'- {TODAY} weekly sitting -- \*\*Not now\*\*: stays on the board; not brought again before {day(14)} unless the card changes', c) is not None
   and r.stdout.startswith('Delete the old audit data (E02-S3): kept as "not now" · '), r.stdout + r.stderr + c)
ok('not now: the card stays out for 14 days (day 13 out, day 14 back)', 'Delete the old audit data (E02-S3)' not in picks(sits(d, 'pick'))
   and 'Delete the old audit data (E02-S3)' not in picks(sits(d, 'pick', '--as-of', day(13))) and 'Delete the old audit data (E02-S3)' in picks(sits(d, 'pick', '--as-of', day(14)))
   and '1 put off as "not now"' in sits(d, 'pick'), sits(d, 'pick', '--as-of', day(13)))
subprocess.run([sys.executable, f'{BIN}/card.py', '--board', f'{d}/board', 'set', 'E02-S3', 'priority=P1'], capture_output=True, text=True)
ok('not now: a card that changes comes back at once', 'Delete the old audit data (E02-S3)' in picks(sits(d, 'pick')), sits(d, 'pick'))
r = sit(d, 'answer', 'E02-S4', 'not now', stdin='x\n')
ok('an answer named "not now" is kept as not now, never as a go', r.returncode == 0 and 'kept as "not now"' in r.stdout and re.match(rf'{TODAY} not-now [0-9a-f]{{12}}$', fmv(d, 'E02-S4', 'sat') or '') is not None, r.stdout + r.stderr)

before = (state(d), text(d, 'E02-S5'))
r1, r2, r3 = sit(d, 'answer', 'E02-S5', 'Go', stdin='x\n'), sit(d, 'answer', 'E02-S1', 'Go', stdin=' \n'), sit(d, 'not-now', 'E02-S99')
ok('refused, nothing written: a card that is not high-stakes, an answer with no words, a card that is not there',
   all(r.returncode not in (0, 3) for r in (r1, r2, r3)) and 'is not a held high-stakes card' in r1.stderr and 'nothing written' in r2.stderr and (state(d), text(d, 'E02-S5')) == before, r1.stderr + r2.stderr + r3.stderr)
ok('the sitting never batches and never starts work: the helper has no verb that starts a card', not re.search(r"verb == '(start|go|all)'", src('sitting.py')) and '--all' not in src('sitting.py'), '')
S = src('status.py')
ok('the sitting\'s numbers are named constants, each with its reason', all(re.search(rf'^{k} = [\d(), ]+#.{{20,}}', S, re.M) for k in ('SIT', 'SIT_EVERY', 'SIT_REST')), 'missing')

# --- the first screen says when a sitting is due: one line, one choice ---
d = board(*QUIET); out = first(d)
ok('first screen, a sitting is due: one line says so', re.search(r'^  Held, high-stakes: 4 cards\. A weekly sitting is due \(none on record\): the \d that free the most other work:$', out, re.M) is not None, out)
opts = re.findall(r'^  \d\. (.*)$', out, re.M)
ok('first screen, a sitting is due: one choice holds it, and says what picking it does', sum(o.startswith('Hold the sitting -- ') for o in opts) == 1
   and any(o.startswith('Hold the sitting -- I bring each card as its own one-click question') for o in opts) and 2 <= len(opts) <= 4, out)
ok('first screen with the sitting choice: at most 25 lines, none over 110, no bare id', len(out.splitlines()) <= 25 and max(map(len, out.splitlines())) <= 110 and not bare(out, titles(d)), bare(out, titles(d)) or out)
d2 = board('--without', 'waiting,ready-pr,stalled-pr,growing,safe-card', '--plan', 'none', '--groom-days', '1'); o2 = first(d2)
ok('nothing else to do and a sitting is due -> the sitting is the recommendation, not "wait"', re.search(r'^  1\. Hold the sitting -- .* \(Recommended\)\n     against: \S', o2, re.M) is not None
   and 'Hold the weekly sitting: 4 held cards wait, and no sitting is on record.' in o2, o2)
sit(d, 'not-now', 'E02-S4'); out = first(d)
ok('first screen, a sitting was held today: no due line, no sitting choice, and the day the next one is due',
   'A weekly sitting is due' not in out and 'Hold the sitting' not in out and f'Held, high-stakes: 4 cards. The next weekly sitting is due {day(7)}' in out, out)
flat = lambda p: re.sub(r'\s+', ' ', open(f'{root}/{p}', encoding='utf-8').read())
d3 = board(*QUIET); add(d3, 'E02-S80', 'Rotate the backup keys', stakes='critical', sat=f'{day(-10)} not-now 000000000000'); o3 = first(d3)
due3 = (re.search(r'^  Held, high-stakes: .*A weekly sitting is due \(.*$', o3, re.M) or [''])[0]
ok('first screen, a sitting last held 10 days ago: the due line names that day and fits in 110 even with 57 held cards', f'(last {day(-10)})' in due3 and len(due3) + 1 <= 110, due3 or o3)
cmd, ref = flat('.claude/commands/backlog-it.md'), flat('.claude/make-it/references/backlog-board.md')
ok('the skill: `sitting` is routed, one question per card, the answers are the specifics, and the helper records each pick',
   '| `sitting` |' in cmd and '## Step 2c -- The weekly sitting' in cmd and 'one AskUserQuestion per card, never batched' in cmd and 'sitting.py --board "$BOARD" --project "$PROJECT" answer <id>' in cmd
   and 'not-now <id>' in cmd and '| Hold the sitting |' in cmd, '')
ok('the skill: each ask is decision-ready -- what it is, what waits and why, 2-4 named answers, one Recommended with its counter-argument',
   all(x in cmd for x in ('what it is, by its title with its id', 'what waits and why, in two plain sentences', '2-4 named answers, each saying what happens', 'exactly one marked Recommended, with the strongest argument against it')), '')
ok('the reference: the sitting, its rule and its record are written down', '### `sitting`' in ref and all(x in ref for x in ('frees the most other cards', 'A bundle counts once', '`SIT_EVERY`', '`SIT_REST`', 'sat: 2026-11-25 answered')), '')

# ============================== EVERY OPEN PULL REQUEST, SORTED ==============================
sort = lambda d, *a, **k: run('sync-prs.py', d, '--repo', f'{d}/board', '--sort', *a, **k)
d = board('--with', 'reviewed,sort-set'); T = titles(d); before = state(d)
out = sort(d)
group = lambda out, name: (re.search(rf'^{name} .*\n((?:  .*\n?)*)', out, re.M) or [0, ''])[1]
want = {'READY': ('#11', 'release it'), 'OUT OF DATE': ('#12', 'rebase it onto main'), 'CAN BE SETTLED': ('#15', '/resolve-it'), 'STALLED': ('#13', 'chase its lane, or take it over'),
        'NEEDS YOU': ('#16', 'a one-click question'), 'WILL NEVER MERGE': ('#17', 'close it with a note and keep its branch')}
for g, (num, action) in want.items():
    body = group(out, g)
    ok(f'sort: {g} holds pull request {num}, and its line says the action ("{action}")', f'({num})' in body and action in body and len(body.strip().splitlines()) == 1, out)
ok('sort: every pull request is in exactly one group, the moving one is counted and not sorted',
   all(sum(f'(#{k})' in group(out, g) for g in want) == 1 for k in (11, 12, 13, 15, 16, 17)) and not any('(#14)' in group(out, g) for g in want) and re.search(r'^Still moving, nothing to do yet \(1\): .*\(#14\)', out, re.M) is not None, out)
ok('sort: each line names the pull request by its own title and number, and the card it is for by title with id',
   '  "fix: refund totals" (#11), for Totals are wrong after a refund (E01-S2): ' in out and '  "chore: tidy the logs" (#13): ' in out and not bare(out, T), bare(out, T) or out)
ok('sort: the card a pull request names in its own title is found (the id is not repeated inside the quoted title)', '"fix: the export header" (#15), for Export drops the last row (E01-S10): a check fails (unit tests)' in out, out)
ok('sort: the first line counts each group', re.search(r'^Open pull requests, sorted -- stand-in · \d{4}-\d\d-\d\d · 7 open: 1 ready · 1 out of date · 1 can be settled · 1 stalled · 1 needs you · 1 will never merge · 1 still moving$', out, re.M) is not None, out)
ok('sort: READY says the three facts it rests on', 'reviewed for this version (' in group(out, 'READY') and 'every check passed' in group(out, 'READY') and 'up to date with main' in group(out, 'READY'), out)
ok('sort: NEEDS YOU carries the question, WILL NEVER MERGE says why', 'Retry, or refile by hand?' in group(out, 'NEEDS YOU') and 'its card, A finished fix (E01-S30), is already closed' in group(out, 'WILL NEVER MERGE'), out)
ok('sort writes nothing', '[exit' not in out and state(d) == before, out)
j = json.loads(run('sync-prs.py', d, '--repo', f'{d}/board', '--sort', '--json'))
ok('sort --json: the same groups, each pull request with its number, head commit, title and card',
   sorted(j['groups']) == sorted(['ready', 'out', 'settle', 'stalled', 'you', 'never', 'moving', 'unread']) and [(r['n'], r['head'], r['title'], r['card']) for r in j['groups']['ready']] == [(11, f'{11:040x}', 'fix: refund totals', 'E01-S2')], j)

for kind, g, says in (('sort-set', 'CAN BE SETTLED', 'every check passed, but no review is recorded for this version: get its independent review'),
                      ('sort-set,reviewed-old', 'CAN BE SETTLED', 'its review was of an earlier version: get this version reviewed'),
                      ('sort-set,reviewed-not-ready', 'CAN BE SETTLED', 'its last review said not ready: send its findings through /resolve-it'),
                      ('sort-set,reviewed,behind', 'OUT OF DATE', '2 commits behind main: rebase it onto main')):
    o = sort(board('--with', kind))
    ok(f'sort ({kind}): the refund pull request is {g} -- "{says}"', '(#11)' in group(o, g) and says in group(o, g) and '(#11)' not in group(o, 'READY'), o)
rel = lambda o: 'Release it -- I bring it up to date if needed' in o  # the first screen offers to release the one reviewed pull request (#11); any other ready one is offered as "I confirm its review"
def edited(kind, **over):  # a board whose refund pull request (#11) has these facts instead
    d = board('--with', kind); rows = json.load(open(f'{d}/prs.json'))
    for x in rows:
        if x['number'] == 11: x.update(over)
    json.dump(rows, open(f'{d}/prs.json', 'w')); return d
for over, g, says in (({'baseRefName': 'feat'}, 'OUT OF DATE', 'it is stacked on feat, not on main'),
                      ({'statusCheckRollup': []}, None, 'no check has run on this version yet'),
                      ({'statusCheckRollup': [{'__typename': 'CheckRun', 'name': 'tests', 'status': 'COMPLETED', 'conclusion': 'SKIPPED'}]}, None, 'no check has run on this version yet')):
    e = edited('sort-set,reviewed', **over); o = sort(e)
    where = group(o, g) if g else (re.search(r'^Still moving.*$', o, re.M) or [''])[0]
    ok(f'sort: reviewed for its head but {says} -> never READY, {g or "still moving"}', '(#11)' not in group(o, 'READY') and '(#11)' in where and (says in where or not g), o)
    ok(f'first screen: the same pull request is not offered as reviewed and ready to release ({says})', not rel(first(e)), first(e))
ok('(control) with every fact right the same pull request is READY and the first screen offers "Release it"', '(#11)' in group(sort(edited('sort-set,reviewed')), 'READY') and rel(first(edited('sort-set,reviewed'))), first(edited('sort-set,reviewed')))
o = sort(board('--with', 'sort-set,reviewed,cannot-compare'))
ok('sort: a pull request whose facts cannot be read is not sorted, and is said so', '(#11)' not in ''.join(group(o, g) for g in want)
   and re.search(r'^NOT SORTED .*\n  "fix: refund totals" \(#11\).*could not tell whether it is behind main', o, re.M) is not None, o)
r = call('sync-prs.py', d, '--repo', f'{d}/board', '--sort', prs=f'{d}/no-such-file.json')
ok('sort: when GitHub cannot be asked it says so, sorts nothing, and exits 2', r.returncode == 2 and 'could not be read' in r.stdout and 'nothing was sorted' in r.stdout and not any(g in r.stdout for g in want), r.stdout + r.stderr)
r = call('sync-prs.py', d, '--sort')
ok('sort with no code folder: says so, sorts nothing', r.returncode == 2 and 'nothing was sorted' in r.stdout + r.stderr, r.stdout + r.stderr)

rec = run('sync-prs.py', d, '--repo', f'{d}/board', '--dry-run')
ok('reconcile --prs ends with the sort, so it happens without anyone remembering', re.search(r'Would close \d+ · waiting \d+\n\nOpen pull requests, sorted -- ', rec) is not None and 'READY -- ' in rec and not bare(rec, T), bare(rec, T) or rec)
out = first(d)
ok('the first screen counts each group in one line', re.search(r'^  Pull requests: 1 ready · 1 out of date · 1 can be settled · 1 stalled · 1 needs you · 1 will never merge$', out, re.M) is not None, out)
ok('first screen with the count: at most 25 lines, none over 110, no bare id', len(out.splitlines()) <= 25 and max(map(len, out.splitlines())) <= 110 and not bare(out, T), bare(out, T) or out)
ok('the stall time is a named constant with its reason', re.search(r'^STALL_HOURS = .*#.{20,}', S, re.M) is not None, '')
git_ops = flat('.claude/make-it/references/git-operations.md')
ok('the skill: the sort runs after every merge and release, and `reconcile --prs` prints it',
   'After every merge and every release' in cmd and 'sync-prs.py "$BOARD" --repo "$REPO" --project "$PROJECT" --sort' in cmd and all(g in ref for g in want) and '### After every merge: every open pull request is sorted' in ref, '')
ok('git-operations: the after-merge step sorts every open pull request into the six groups', 'After every merge, sort every open pull request' in git_ops and all(g in git_ops for g in want), '')
ok('the skill: each group has its action -- release, rebase, /resolve-it, chase or take over, a one-click ask, close with a note and keep the branch',
   all(x in cmd for x in ('| READY |', '| OUT OF DATE |', '| CAN BE SETTLED |', '| STALLED |', '| NEEDS YOU |', '| WILL NEVER MERGE |', '`/resolve-it`', 'keep the branch')), '')
r = subprocess.run([sys.executable, f'{BIN}/sync-prs.py', '--self-test'], capture_output=True, text=True, encoding='utf-8')
ok('sync-prs.py --self-test passes', r.returncode == 0, r.stderr)
sys.exit(fail)
PY
