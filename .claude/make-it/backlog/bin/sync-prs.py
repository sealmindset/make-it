#!/usr/bin/env python3
"""Move bug cards forward from facts: every PR in a card's `pr:` closed and one merged -> Live (only
with a `signal:` -- else it waits, named);
Checked -> done. Forward only -- never back, never past Live without the live check.

Usage: sync-prs.py [board_dir] --repo PATH [--project NAME] [--dry-run]
       sync-prs.py --self-test
  --repo  the code repo whose PRs bare numbers in `pr:` name (settings `repo`); `gh` reads its
          remote. A PR in another repo goes in `pr:` as its full URL. With no --repo, no `gh` or
          no auth, the PR step is skipped and said so; Checked -> done still runs.
  Merged is not deployed: Live here means merged, and the live check confirms the deploy.
  Writes the cards and BOARD.md; the caller commits them (the board's sync step).
"""
import datetime, importlib.util, json, os, re, subprocess, sys

_bin = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(_bin, 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
_cspec = importlib.util.spec_from_file_location('card', os.path.join(_bin, 'card.py'))
C = importlib.util.module_from_spec(_cspec); _cspec.loader.exec_module(C)  # the one card writer
v = R.v
BEFORE_LIVE = ('Reported', 'Cause found', 'Fix ready')
URL = r'https?://[^\s,\]]+/pull/\d+'

def prs(d):
    """pr: [1590, 1593] · 1590 · #1590 · full PR URLs (any repo). None for a repo#N short form."""
    s = v(d, 'pr'); rest = re.sub(URL, ' ', s)
    if re.search(r'\w#\d', rest): return None  # "splashdown#71": which repo is ambiguous -- ask for the URL
    return re.findall(URL, s) + [int(n) for n in re.findall(r'\d+', rest)]

def name(n): return f'#{n}' if isinstance(n, int) else '{}#{}'.format(*re.search(r'([^/]+)/pull/(\d+)$', n).groups())

def gh(repo):
    """A cached PR lookup through `gh` (number or URL -> {state, mergedAt}), or None when gh can't run."""
    try:
        if subprocess.run(['gh', 'auth', 'status'], cwd=repo, capture_output=True, timeout=30).returncode: return None
    except (OSError, subprocess.TimeoutExpired): return None
    cache = {}
    def look(n):
        if n not in cache:
            try:
                r = subprocess.run(['gh', 'pr', 'view', str(n), '--json', 'state,mergedAt'], cwd=repo, capture_output=True, text=True, timeout=30)
                cache[n] = json.loads(r.stdout) if r.returncode == 0 else {'state': 'UNKNOWN', 'why': (r.stderr.strip().splitlines() or ['?'])[-1][:70]}
            except subprocess.TimeoutExpired: cache[n] = {'state': 'UNKNOWN', 'why': 'gh timed out'}
        return cache[n]
    return look

def eligible(d, closing):  # still movable right now: open, and at the stage the move starts from
    return v(d, 'status') != 'done' and (v(d, 'stage') == 'Checked' if closing else v(d, 'stage') in BEFORE_LIVE)

def moves(B, look):
    """([(path, changes, note)], [(path, why it waits)]) -- what would move, and what can't yet."""
    out, wait = [], []
    for p, d in R.load(B).items():
        if '/stories/' not in p: continue
        if eligible(d, True): out.append((p, {'status': 'done'}, 'Checked → done (the live check passed)')); continue
        if not eligible(d, False): continue
        nums = prs(d)
        if nums is None: wait.append((p, 'pr: names another repo by short form -- use the PR URL')); continue
        if not nums:
            if v(d, 'stage') == 'Fix ready': wait.append((p, 'no pr: -- set it to the fix PR'))
            continue
        if not look: wait.append((p, 'PR step skipped')); continue
        got = {n: look(n) for n in nums}
        blocking = [f"{name(n)} {s['state'].lower()}" + (f" ({s['why']})" if s.get('why') else '') for n, s in got.items() if s['state'] in ('OPEN', 'UNKNOWN')]
        if blocking or not any(s['state'] == 'MERGED' for s in got.values()):
            wait.append((p, ', '.join(blocking) or ', '.join(f'{name(n)} closed without merging' for n in nums))); continue
        if not v(d, 'signal'):  # the Live gate: how the fix is proved on the live system, written before it counts as shipped
            wait.append((p, 'merged, but no signal: -- write how the fix is checked live (card.py set <id> signal=...)')); continue
        note = f"{v(d, 'stage')} → Live · " + ', '.join(f"{name(n)} merged {s['mergedAt'][:10]}" for n, s in got.items() if s['state'] == 'MERGED')
        note += ' (deploy not checked -- the live check confirms it)'
        if v(d, 'decision'): note += ' · it still has a decision: -- clear it if that was answered'
        out.append((p, {'stage': 'Live'}, note))
    return out, wait

def apply(p, changes, note, T):
    """Write the move through card.py's writer. False if the card moved meanwhile."""
    # ponytail: re-read at write time -- another session may have moved the card while gh ran
    if not eligible(R.fm(p), 'status' in changes): return False
    C.write(p, changes, f'PR sync ({T})', f'- {note}', T)
    return True

def run(B, look, dry, proj=None, T=None):
    T = T or datetime.date.today()
    out, wait = moves(B, look)
    cards = R.load(B)
    cid = lambda p: v(cards[p], 'id')
    if not dry: C.lock(B); out = [(p, ch, note) for p, ch, note in out if apply(p, ch, note, T)]  # card.py's writer lock
    if out and not dry:
        subprocess.run([sys.executable, os.path.join(_bin, 'regen-board.py'), B] + (['--project', proj] if proj else []), check=True)
    lines = [f"PR sync -- {proj or os.path.basename(B)} · {T}" + (' · no --repo or gh: PR step skipped' if not look else '') + (' · dry run, nothing written' if dry else '')]
    lines += [f'  {cid(p)} · {note}' for p, _, note in out] or ['  nothing to move']
    lines += ['Waiting:'] + [f'  {cid(p)} · {why}' for p, why in wait] if wait else []
    lines.append(f"{'Would move' if dry else 'Moved'} {len(out)} · waiting {len(wait)}")
    return '\n'.join(lines)

def self_test():
    import tempfile
    T = datetime.date.today()
    with tempfile.TemporaryDirectory() as t:
        S = f'{t}/items/EPIC-01-bugs/stories'; os.makedirs(S)
        def card(n, body='', **kv):
            open(f'{S}/S{n}.md', 'w').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in {'id': f'E01-S{n}', 'type': 'breakfix', 'status': 'in-progress', **kv}.items()) + f'---\n{body}')
        open(f'{t}/items/EPIC-01-bugs/epic.md', 'w').write('---\nid: E01\ntitle: Bugs\nstatus: in-progress\n---\n')
        url = 'https://github.com/org2/repo1/pull/109'
        card(1, stage='Fix ready', pr='[101]', priority='P1', signal='log: ok')     # merged -> Live
        card(17, stage='Fix ready', pr='[101]')                                     # merged, no signal -> waits (the Live gate)
        card(2, stage='Fix ready', pr='[102, 103]')                                 # one still open -> waits
        card(3, stage='Cause found', pr='104')                                      # closed unmerged -> waits
        card(4, stage='Checked')                                                    # -> done
        card(5, stage='Live', pr='[105]')                                           # already Live: never past it
        card(6, '\nFixed in PR #106.\n', stage='Fix ready')                         # no pr: -> waits, never guessed
        card(8, stage='Fix ready', pr='[101]', status='done')                       # done: left alone
        card(9, stage='Fix ready', pr=url, signal='page shows it')                  # another repo's PR, by URL
        card(10, stage='Fix ready', pr='[110]', decision='Ratify #110?', signal='x') # moves, flags the decision
        card(12, stage='Fix ready', pr='splashdown#71')                             # short form: ambiguous -> waits
        card(13, stage='Needs decision', pr='[101]')                                # older waiting form: left alone
        open(f'{S}/S11.md', 'w').write('---\nid: E01-S11\ntype: story\nstatus: in-progress\npr: [101]\n---\n')  # no stage: untouched
        st = {101: 'MERGED', 102: 'MERGED', 103: 'OPEN', 104: 'CLOSED', 105: 'MERGED', 106: 'MERGED', 109: 'OPEN', url: 'MERGED', 110: 'MERGED', 71: 'MERGED'}
        look = lambda n: {'state': st.get(n, 'UNKNOWN'), 'mergedAt': '2026-10-15T10:00:00Z'}
        before = {p: open(p).read() for p in R.load(t)}
        out = run(t, look, dry=True, proj='t', T=T)
        assert {p: open(p).read() for p in R.load(t)} == before and not os.path.exists(f'{t}/BOARD.md') and 'Would move 4' in out, out
        out = run(t, look, dry=False, proj='t', T=T)
        c = {v(d, 'id'): d for d in R.load(t).values()}
        assert [v(c[f'E01-S{n}'], 'stage') for n in (1, 2, 3, 5, 6, 9, 10, 12, 13)] == ['Live', 'Fix ready', 'Cause found', 'Live', 'Fix ready', 'Live', 'Live', 'Fix ready', 'Needs decision'], out
        assert v(c['E01-S4'], 'status') == 'done' and v(c['E01-S8'], 'status') == 'done' and v(c['E01-S11'], 'stage') == '', out
        assert v(c['E01-S6'], 'pr') == '' and v(c['E01-S1'], 'updated') == str(T) and v(c['E01-S1'], 'priority') == 'P1', out
        assert 'E01-S2 · #103 open' in out and 'E01-S3 · #104 closed without merging' in out and 'E01-S6 · no pr:' in out, out
        assert 'E01-S17 · merged, but no signal:' in out and v(R.fm(f'{S}/S17.md'), 'stage') == 'Fix ready', out
        assert 'E01-S9 · Fix ready → Live · repo1#109 merged' in out and 'E01-S12 · pr: names another repo by short form' in out, out
        assert not any(f'E01-S{n} ' in out for n in (5, 8, 11, 13)), out  # Live, done, stage-less, older waiting form
        assert 'clear it if that was answered' in out and 'deploy not checked' in out and '## PR sync' in open(f'{S}/S1.md').read(), out
        assert '**Live, to check:** S1, S5, S9, S10' in open(f'{t}/BOARD.md').read(), open(f'{t}/BOARD.md').read()
        assert not [f for f in os.listdir(S) if f.endswith('.tmp')], os.listdir(S)
        out = run(t, look, dry=False, proj='t', T=T)  # nothing left to move: idempotent
        assert 'nothing to move' in out and 'Moved 0' in out, out
        card(14, stage='Checked'); card(15, stage='Fix ready', pr='[101]')
        out = run(t, None, dry=False, proj='t', T=T)  # no gh: Checked still closes, PR cards wait
        assert 'E01-S15 · PR step skipped' in out and v(R.fm(f'{S}/S14.md'), 'status') == 'done' and v(R.fm(f'{S}/S15.md'), 'stage') == 'Fix ready', out
        card(16, stage='Fix ready', pr='[101]', signal='x')  # another session closes it while gh runs: the write is refused
        late = lambda n: (card(16, stage='Checked', status='done'), look(n))[1]
        out = run(t, late, dry=False, proj='t', T=T)
        assert v(R.fm(f'{S}/S16.md'), 'stage') == 'Checked' and 'E01-S16' not in out, out
    print('sync-prs self-test: OK')

if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']: self_test(); sys.exit(0)
    opts = {}
    for k in ('--repo', '--project'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'sync-prs: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    dry = '--dry-run' in args; args = [a for a in args if a != '--dry-run']
    if len(args) > 1 or any(a.startswith('--') for a in args): sys.exit(f'sync-prs: unexpected {args}')
    B = os.path.abspath(os.path.expanduser(args[0] if args else os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'sync-prs: no items/ folder in {B}')
    print(run(B, gh(os.path.expanduser(opts['--repo'])) if '--repo' in opts else None, dry, opts.get('--project')))
