#!/usr/bin/env bash
# /backlog-it's first screen says what to do next, and every board helper names a card by its title with its id.
# Proven by RUNNING the helpers on a stand-in board (scripts/backlog-stand-in/make-board.py: a temp git repo with
# cards in every state the rule cares about) with a stand-in `gh` (scripts/backlog-stand-in/gh) for the
# pull-request facts. Nothing here touches a real board or the network.
#   - The next-thing rule, one run per branch, in the rule's order: a question waits on the owner -> answer it; a
#     pull request is ready -> release it; pull requests are stuck or out of date -> sort them; the plan's next wave
#     can start and a lane is free -> start it; the plan is stale (ran out, stuck, or most cards that can start are
#     not in it) -> plan; the pile grew two weeks running, or the last groom is old -> groom; else the next safe
#     card; else wait. Each run checks the sentence, the cards or pull requests it names (title with id), and the
#     choices: 2-4, each `Name -- what happens`, exactly one Recommended with its `against:`, the next branches of
#     the rule as the other choices.
#   - The screen: four parts in order, at most 25 lines; only what needs the owner (each question one line; held
#     high-stakes cards as a count with the few that free the most other work); what changed since the last look
#     (a mark file the board's git never sees) or in the last 24 hours; one trend line.
#   - Plain words: no line any helper prints holds a card id without its title in front ("Title (E01-S2)"), with a
#     control that the detector fails on a bare id.
#   - The skill and its reference route the bare command to the first screen and ask the choices as a select.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 -I - "$root" "$t" <<'PY'
import json, os, re, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
BIN, STAND = f'{root}/.claude/make-it/backlog/bin', f'{root}/scripts/backlog-stand-in'
fail = 0
def ok(name, cond, detail=''):
    global fail
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else f'\n     {str(detail)[-1500:]}'))
    fail |= not cond

n = [0]
def board(*args):
    n[0] += 1; d = f'{tmp}/b{n[0]}'
    subprocess.run([sys.executable, f'{STAND}/make-board.py', d, *args], check=True)
    return d
def run(helper, d, *args, gh=True):
    env = dict(os.environ, GH_STUB_PRS=f'{d}/prs.json', PATH=(STAND + os.pathsep if gh else '') + os.environ['PATH'])
    r = subprocess.run([sys.executable, f'{BIN}/{helper}', f'{d}/board', '--project', 'stand-in', *args], capture_output=True, text=True, encoding='utf-8', env=env)
    return r.stdout + (f'\n[exit {r.returncode}] {r.stderr}' if r.returncode or r.stderr else '')
first = lambda d, *a, **k: run('status.py', d, '--first', '--repo', f'{d}/board', '--lane-cap', '3', *a, **k)

def titles(d):
    out = {}
    for dp, _, fs in os.walk(f'{d}/board/items'):
        for f in fs:
            txt = open(os.path.join(dp, f), encoding='utf-8').read()
            i, ti = re.search(r'^id: (.+)$', txt, re.M), re.search(r'^title: "?(.*?)"?$', txt, re.M)
            if i: out[i.group(1)] = ti.group(1) if ti else ''
    return out
ID = re.compile(r'\bE\d+(?:-S\d+)?\b')
def bare(text, T):
    """Every line that holds a card id without that card's title in front of it: `Title (ID)`, the title whole
    or shortened to its first words and an ellipsis."""
    bad = []
    for line in text.splitlines():
        for m in ID.finditer(line):
            t = T.get(m.group(0)) or 'Untitled card'
            pre = line[:m.start()]
            named = pre.endswith(' (') and line[m.end():m.end() + 1] == ')'
            pre = pre[:-2]
            whole = pre.endswith(t)
            short = pre.endswith('…') and any(pre[:-1].endswith(t[:k]) for k in range(8, len(t)))
            if not (named and (whole or short)): bad.append(line); break
    return bad

def parts(out):  # the sentence, the choices, and the section headings in order
    lines = out.splitlines()
    heads = [l.split('  ')[0].split(' (')[0] for l in lines if re.match(r'[A-Z][A-Z 0-9]+\b', l) and not l.startswith(' ')]
    i = lines.index('DO NEXT') if 'DO NEXT' in lines else -1
    sent = lines[i + 1].strip() if i >= 0 else ''
    opts = [l.strip() for l in lines[i + 2:i + 7] if re.match(r'  \d\. ', l)] if i >= 0 else []
    return heads, sent, opts
def shape(name, out, label, second=None):
    heads, sent, opts = parts(out)
    ok(f'{name}: four parts in order, at most 25 lines', [h for h in heads if h in ('DO NEXT', 'NEEDS YOU', 'SINCE YOU LAST LOOKED', 'IN THE LAST 24 HOURS', 'TREND')][:4]
       in (['DO NEXT', 'NEEDS YOU', 'IN THE LAST 24 HOURS', 'TREND'], ['DO NEXT', 'NEEDS YOU', 'SINCE YOU LAST LOOKED', 'TREND']) and len(out.splitlines()) <= 25, out)
    rec = [o for o in opts if 'Recommended' in o]
    ok(f'{name}: 2-4 choices, each `Name -- what happens`, one Recommended with its against:',
       2 <= len(opts) <= 4 and all(re.match(r'\d\. [A-Z][^-]+ -- \S', o) for o in opts) and len(rec) == 1 and rec[0] == opts[0] and '(Recommended; against: ' in rec[0]
       and opts[-1].startswith(f'{len(opts)}. Full status -- '), out)
    ok(f'{name}: the recommended choice is "{label}"' + (f', then "{second}"' if second else ''),
       bool(opts) and opts[0].startswith(f'1. {label} -- ') and (not second or opts[1].startswith(f'2. {second} -- ')), out)
    return sent

OFF = ['waiting', 'ready-pr', 'stalled-pr', 'growing', 'safe-card']
without = lambda k: ['--without', ','.join(OFF[:k])] if k else []
# --- the rule, one branch per run, in order ---
d = board(); T = titles(d); out = first(d); s = shape('answer', out, 'Answer now', 'Release it')
ok('a question waits on the owner -> answer it, the card named by title with id', s.startswith('Answer the question that waits on you') and 'Filings give up after two tries (E01-S3)' in s, out)
ok('answer: no line holds a bare card id', not bare(out, T), bare(out, T))
ok('only what needs you: the question is one line -- the title with its id, then what waits and the question',
   '\n  Filings give up after two tries (E01-S3): The retry job gave up on 3 filings after two tries; nothing else waits on them. Retry, or refile by hand?\n' in out, out)
held = out.split('NEEDS YOU')[1].split('\n\n')[0] if 'NEEDS YOU' in out else ''
ok('held high-stakes cards are a count, then the few that free the most other work, most first',
   'Held, high-stakes: 4 cards.' in held and re.search(r'Move sign-in to the new provider \(E02-S1\) -- frees 3 other cards\n\s+Change the billing tables \(E02-S2\) -- frees 3 other cards', held) is not None
   and 3 <= len(re.findall(r'^    \S', held, re.M)) <= 5, out)
ok('the pull request that is moving is never mentioned', '#14' not in out and 'a new report page' not in out, out)

d = board(*without(1)); out = first(d); s = shape('release', out, 'Release it', 'Sort them')
ok('a pull request is ready -> release it, named by its card', s.startswith('Release ') and 'Totals are wrong after a refund (E01-S2)' in s and '#11' in s and 'checks pass' in s, out)
ok('release: nothing waits on you is said in one line', '\n  Questions: nothing waits on you\n' in out, out)
ok('release: no bare card id', not bare(out, T), bare(out, T))
nogh = run('status.py', d, '--first', '--lane-cap', '3')
ok('with no --repo the pull-request steps are skipped and said so, and the rule goes on to the plan', 'pull requests not checked' in nogh and parts(nogh)[2][:1] and parts(nogh)[2][0].startswith('1. Start the wave -- '), nogh)

d = board(*without(2)); out = first(d); s = shape('sort', out, 'Sort them', 'Start the wave')
ok('pull requests stuck or out of date -> sort them, each named with why', s.startswith('Sort the 2 pull requests') and 'Search is slow on big accounts (E01-S4)' in s and 'behind main' in s
   and '"chore: tidy the logs" (#13)' in out and '#14' not in out, out)
ok('sort: no bare card id', not bare(out, T), bare(out, T))

d = board(*without(3)); out = first(d); s = shape('dispatch', out, 'Start the wave', 'Groom')
ok('the plan has a wave that can start and lanes are free -> start that wave, its cards named', s.startswith('Start wave 1 of the plan') and all(x in s for x in
   ('Export drops the last row (E01-S10)', 'Search ignores accents (E01-S11)', 'Upload fails on big files (E01-S12)')) and '3 of 3 lanes are free' in s, out)
ok('dispatch: no bare card id', not bare(out, T), bare(out, T))

for plan, why in (('ran-out', 'every wave in the plan is done'), ('stuck', 'the next wave waits on Move sign-in to the new provider (E02-S1)'),
                  ('share', '2 of the 2 cards that can start are not in the plan')):
    d = board(*without(3), '--plan', plan); out = first(d); s = shape(f'plan ({plan})', out, 'Plan')
    ok(f'the plan is stale ({plan}) -> plan, with the reason', s.startswith('Make a new plan') and why in s, out)
    ok(f'plan ({plan}): no bare card id', not bare(out, titles(d)), bare(out, titles(d)))

d = board(*without(3), '--plan', 'none', '--groom-days', '10'); out = first(d); s = shape('groom (growing)', out, 'Groom', 'Start it')
ok('more cards opened than closed two weeks running -> groom, with the numbers', s.startswith('Groom the board') and 'two weeks running' in s and '2 opened, 0 closed' in s and '4 opened, 1 closed' in s, out)
ok('the trend line says the pile grew and the biggest reason', re.search(r'^TREND  This week: 2 opened, 0 closed: the pile grew by 2, mostly new bugs \(2 of 2\)\.$', out, re.M) is not None, out)
d = board(*without(4), '--plan', 'none', '--groom-days', '20'); out = first(d); s = shape('groom (old)', out, 'Groom', 'Start it')
ok('the last groom is older than the set age -> groom', s.startswith('Groom the board') and 'the last groom was 20 days ago' in s, out)
ok('the trend line says the pile shrank and the biggest reason', re.search(r'^TREND  This week: 2 opened, 6 closed: the pile shrank by 4, with 6 fixes shipped\.$', out, re.M) is not None, out)
d = board(*without(3), '--plan', 'none', '--groom-days', '1'); out = first(d)
ok('a board groomed yesterday is not told to groom again, even while the pile grows', parts(out)[2][:1] and parts(out)[2][0].startswith('1. Start it -- '), out)

d = board(*without(4), '--plan', 'none', '--groom-days', '1'); out = first(d); s = shape('next safe card', out, 'Start it')
ok('otherwise -> the next safe card, named', s.startswith('Start "Export drops the last row (E01-S10)"') and 'nothing it waits on is open' in s, out)
ok('next safe card: no bare card id', not bare(out, titles(d)), bare(out, titles(d)))

d = board(*without(5), '--plan', 'none', '--groom-days', '1'); out = first(d); s = shape('wait', out, 'Wait')
ok('nothing can start -> wait, said plainly', s.startswith('Nothing to start right now') and 'wait' in s.lower(), out)

# --- what changed since last time ---
d = board(*without(4), '--plan', 'none', '--groom-days', '1'); B = f'{d}/board'
git = lambda *a: subprocess.run(['git', '-C', B, *a], capture_output=True, text=True, encoding='utf-8').stdout
out = first(d)
ok('first look: no mark yet, so the last 24 hours, in three lines', re.search(r'\nIN THE LAST 24 HOURS.*\n  Shipped: 6 -- .*\n  Found:   1 -- The export button does nothing for one role \(E01-S21\)\n  Stuck:   nothing\n', out) is not None, out)
ok('a plain look writes nothing to the board', not os.path.exists(f'{B}/.last-seen.json') and git('status', '--porcelain') == '', git('status', '--porcelain'))
first(d, '--seen')
ok('--seen keeps the mark in the board folder, and the board\'s git never sees it', os.path.exists(f'{B}/.last-seen.json') and git('status', '--porcelain') == '' and git('ls-files', '.last-seen.json') == '', git('status', '--porcelain'))
mark = open(f'{B}/.last-seen.json', encoding='utf-8').read()
p = f'{B}/items/EPIC-01-bugs/stories'
txt = open(f'{p}/S12.md', encoding='utf-8').read(); open(f'{p}/S12.md', 'w', encoding='utf-8').write(txt.replace('status: backlog', 'status: done'))
open(f'{p}/S50.md', 'w', encoding='utf-8').write('---\nid: E01-S50\ntitle: "The login page shows the wrong year"\ntype: breakfix\nstatus: backlog\nstage: Reported\npriority: P3\n---\n')
txt = open(f'{p}/S11.md', encoding='utf-8').read()
open(f'{p}/S11.md', 'w', encoding='utf-8').write(re.sub(r'updated: .*', 'updated: 2020-01-01', txt.replace('status: backlog', 'status: in-progress')))
subprocess.run(['git', '-C', B, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qam', 'x', '--date', '2020-01-01T00:00:00'],
               check=True, env=dict(os.environ, GIT_COMMITTER_DATE='2020-01-01T00:00:00'))
out = first(d)
ok('since the last look: what shipped, what was found, what got stuck, each named',
   re.search(r'\nSINCE YOU LAST LOOKED \(\d{4}-\d\d-\d\d \d\d:\d\d\)\n  Shipped: 1 -- Upload fails on big files \(E01-S12\)\n  Found:   1 -- The login page shows the wrong year \(E01-S50\)\n  Stuck:   1 -- Search ignores accents \(E01-S11\)\n', out) is not None, out)
ok('a look without --seen leaves the mark as it was', open(f'{B}/.last-seen.json', encoding='utf-8').read() == mark)
ok('since the last look: no bare card id', not bare(out, titles(d)), bare(out, titles(d)))

# --- plain words in everything else the helpers print ---
d = board(); T = titles(d)
for name, out in (('status', run('status.py', d)), ('status --needs-you', run('status.py', d, '--needs-you')),
                  ('sync-prs --dry-run', run('sync-prs.py', d, '--dry-run')), ('sync-prs --dry-run with gh', run('sync-prs.py', d, '--repo', f'{d}/board', '--dry-run'))):
    ok(f'{name}: runs, and no line holds a bare card id', '[exit' not in out and len(out) > 40 and not bare(out, T), (bare(out, T) or out))
st = run('status.py', d)
ok('status still prints everything the old board did (in flight, up next, burn-down, needs you, drift, epics, cycle time)',
   all(h in st for h in ('IN FLIGHT', 'UP NEXT', 'BURN-DOWN', 'NEEDS YOU', 'DRIFT', 'EPICS', 'CYCLE TIME')), st)
ok('status reads a plan written with titles: the next wave, its cards named', 'next wave: wave 1 (dispatch-it): Export drops the last row (E01-S10), Search ignores accents (E01-S11), Upload fails on big files (E01-S12)' in st, st)
ok('(control) the detector fails on a bare id, an id beside the wrong title, and passes a shortened title',
   bare('  E01-S3 · Filings give up', T) and bare('Start E01-S10 now', T) and bare('Search ignores accents (E01-S10)', T)
   and not bare('x Filings give up after two tries (E01-S3) y', T) and not bare('Filings give up… (E01-S3)', T) and bare('up… (E01-S3)', T))

# --- the rule's numbers are named, and the skill presents and asks ---
src = open(f'{BIN}/status.py', encoding='utf-8').read()
ok('the thresholds are named constants, each with a comment saying why',
   all(re.search(rf'^{k} = [\d.(), ]+#.{{20,}}', src, re.M) for k in ('PR_STALL', 'PLAN_STALE', 'GROW_WEEKS', 'GROOM_AGE', 'GROOM_REST', 'SIT')), 'missing')
flat = lambda p: re.sub(r'\s+', ' ', open(f'{root}/{p}', encoding='utf-8').read())
cmd, ref = flat('.claude/commands/backlog-it.md'), flat('.claude/make-it/references/backlog-board.md')
ok('the skill: bare /backlog-it and `board` run the first screen and mark it seen',
   '| *(none)*, `board` | The first screen' in cmd and 'status.py "$BOARD" --project "$PROJECT" --repo "$REPO" --lane-cap "$LANE_CAP" --first --seen' in cmd, '')
ok('the skill: the choices are asked as one select, taken from the helper as printed', 'ask its choices with AskUserQuestion, exactly as printed' in cmd and 'The helper decides; you present and ask' in cmd, '')
ok('the skill: the old compact board stays under `list`, and `status` is unchanged', '| `list` / `show` | The compact board' in cmd and '| `status` (no id) |' in cmd, '')
ok('the reference: the first screen and its rule are written down, in order', '### The first screen' in ref and all(x in ref for x in
   ('**The next-thing rule**', 'answer it', 'release it', 'sort them', 'start that wave', 'plan', 'groom', 'the next safe card', '.last-seen.json', '.git/info/exclude')), '')
for h in ('status.py', 'regen-board.py', 'sync-prs.py'):
    r = subprocess.run([sys.executable, f'{BIN}/{h}', '--self-test'], capture_output=True, text=True, encoding='utf-8')
    ok(f'{h} --self-test passes', r.returncode == 0, r.stderr)
sys.exit(fail)
PY
