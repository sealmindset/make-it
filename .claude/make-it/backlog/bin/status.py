#!/usr/bin/env python3
"""Print where the board stands: in flight, up next, burn-down + forecast, needs you, drift,
epics, and cycle time. Read-only, no AI call -- the same board gives the same answer.

Usage: status.py [board_dir] [--project NAME] [--needs-you]
       status.py --self-test
  Dates come from the board's git history (when a card went done, Live or Checked, and when it
  last changed). With no git history, from each card's created: and updated:.
"""
import datetime, importlib.util, os, re, statistics, subprocess, sys

_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
v, D = R.v, datetime.timedelta
WEEKS, STALL, LANE, TOP = 4, 14, 2, 5  # ponytail: fixed window, stall thresholds (work / a lane) and list cap; flags if anyone needs them

def day(s):
    try: return datetime.date.fromisoformat(s.strip())
    except ValueError: return None

def history(B):
    """({card path: {added, added_stage, added_done, done, live, checked, touched}}, first date, source)."""
    git = lambda *a: subprocess.run(['git', '-C', B, *a], capture_output=True, text=True, errors='replace')
    pre = git('rev-parse', '--show-prefix')
    if pre.returncode: return {}, None, 'card dates (no git history)'
    log = git('-c', 'core.quotePath=false', 'log', '--no-color', '--src-prefix=a/', '--dst-prefix=b/', '--reverse', '-p', '-M',
              '--format=@@C %cd', '--date=short', '--', 'items').stdout
    if not log: return {}, None, 'card dates (no git history)'
    key, H, date, cur, new, frm = {}, {}, None, None, False, None  # key: every path a card had -> its history's key
    for l in log.splitlines():
        if l.startswith('@@C '): date = l[4:]
        elif l.startswith('diff --git '):  # "a/P b/P": the same path twice unless renamed (the rename lines say so)
            p = l[13:][:(len(l) - 16) // 2] if l.startswith('diff --git a/') else l  # ponytail: a still-quoted path gets a junk key
            cur = key.setdefault(p, p); new = False
            H.setdefault(cur, {})['touched'] = date
        elif l.startswith('rename from '): frm = l[12:]
        elif l.startswith('rename to '):
            cur = key[l[10:]] = key.get(frm, frm)
            H.setdefault(cur, {})['touched'] = date
        elif l.startswith('new file mode'):  # a new card, even at a path an older card once had
            new = True; cur = key[p] = f'{p}@{date}'; H[cur] = {'touched': date, 'added': date}
        elif re.match(r'\+status:\s*done\s*$', l): H[cur]['done'] = date; H[cur]['added_done'] = new
        elif m := re.match(r'\+stage:\s*(.+?)\s*$', l):
            if new: H[cur].setdefault('added_stage', m.group(1))
            if m.group(1) in ('Live', 'Checked'): H[cur].setdefault(m.group(1).lower(), date)
    prefix = pre.stdout.strip()
    src = 'git history' if not prefix else f"git history of branch {git('rev-parse', '--abbrev-ref', 'HEAD').stdout.strip()}"
    hist = {p: H.get(key.get(prefix + os.path.relpath(p, B), ''), {}) for p in R.load(B)}
    first = min((x['added'] for x in hist.values() if x.get('added')), default='')  # the board's cards, not archived ones
    return hist, day(first), src

def forecast(rows, open_now, T):
    """rows: [(opened, closed)] per week. The average net decides it."""
    if not open_now: return 'nothing open'
    if not rows: return 'no full week of history yet'
    net, rate = sum(o - c for o, c in rows) / len(rows), sum(c for _, c in rows) / len(rows)
    if net < 0:
        wks = open_now / -net
        return f'shrinking {net:+.1f}/wk: clear in ~{wks:.0f} wks (~{T + D(weeks=wks)})'
    s = f'growing {net:+.1f}/wk: no finish at this rate' if net else 'flat: no finish at this rate'
    return s + (f' · with no new cards, ~{open_now / rate:.1f} wks at {rate:.1f} closed/wk' if rate else '')

def facts(B, T=None):
    T = T or datetime.date.today()
    cards = R.load(B)
    H, first, src = history(B)
    h = lambda p: H.get(p, {})
    status = {v(d, 'id').upper(): v(d, 'status') for d in cards.values()}
    leaf = {p: d for p, d in cards.items() if '/stories/' in p}
    op = {p: d for p, d in leaf.items() if v(d, 'status') != 'done'}
    title = lambda d: v(d, 'title').strip('"')
    opened = lambda p, d: day(v(d, 'created')) or day(h(p).get('added', '')) or datetime.date.min
    # last change: the later of git's last commit and the card's own updated: (a lane's write may not be committed yet)
    last = lambda p, d: max(filter(None, (day(h(p).get('touched', '')), day(v(d, 'updated')))), default=None) or opened(p, d)
    idle = lambda p, d: (T - last(p, d)).days
    def done_on(p, d):  # the last commit that set it done; else (or if it entered git done) its own updated:
        x = h(p)
        return day(x['done']) if x.get('done') and not x.get('added_done') else day(v(d, 'updated')) or datetime.date.min
    dn = {p: done_on(p, d) for p, d in leaf.items() if v(d, 'status') == 'done'}
    seen = [p for p in leaf if not h(p).get('added_done')]  # a card that entered git already done (an import) was opened and closed before
    rows = []
    for w in range(WEEKS):
        end = T - D(days=7 * w); start = end - D(days=7)
        if first and end < first: break
        rows.append((end, sum(start < opened(p, leaf[p]) <= end for p in seen),
                     sum(start < dn[p] <= end for p in seen if p in dn),
                     sum(opened(p, d) <= end and not (p in dn and dn[p] <= end) for p, d in leaf.items())))
    bug = lambda d: v(d, 'type') == 'breakfix'
    pick = lambda pred: sorted((p for p, d in op.items() if pred(d)), key=lambda p: -idle(p, op[p]))
    flight = {k: pick(lambda d: R.bucket(d) == k) for k in ('Now fixing', 'Shipping', 'Live, to check')}  # the board's own lines
    flight['Other work'] = pick(lambda d: not bug(d) and not R.bucket(d) and v(d, 'status') == 'in-progress')
    epics = {os.path.dirname(p): d for p, d in cards.items() if p.endswith('/epic.md')}
    kids = lambda e: [p for p in leaf if os.path.dirname(os.path.dirname(p)) == e]
    next_bugs = []  # the board's own Next up, per bug epic
    for e in sorted(epics):
        if any(bug(leaf[p]) for p in kids(e)):
            short = R.next_up([leaf[p] for p in kids(e)], status)
            next_bugs += [p for p in kids(e) if v(leaf[p], 'id').split('-')[-1] == short]
    parents = {v(d, 'parent').upper() for d in cards.values()}
    can = sorted((p for p, d in op.items() if not bug(d) and v(d, 'status') in ('backlog', 'ready')
                  and v(d, 'id').upper() not in parents and not R.blocked(d, status)),
                 key=lambda p: (v(op[p], 'priority') or 'P9', opened(p, op[p]), p))
    plan, pf = None, os.path.join(B, 'PLAN.md')
    if os.path.exists(pf):
        txt = open(pf).read(); pd = day((re.search(r'\d{4}-\d{2}-\d{2}', txt.split('\n', 1)[0]) or [''])[0])
        cand = [p for p, d in op.items() if v(d, 'status') in ('backlog', 'ready', 'designing') and v(d, 'id').upper() not in parents]
        changed = sum(not pd or last(p, op[p]) > pd or not re.search(rf"\b{re.escape(v(op[p], 'id'))}\b", txt) for p in cand)  # dispatch's rule
        waves = re.findall(r'^\d+\. .*$', txt.split('## Waves', 1)[-1].split('\n## ', 1)[0], re.M)
        merged = lambda i: status.get(i, 'done') == 'done' or any(v(d, 'id').upper() == i and v(d, 'stage') in ('Live', 'Checked') for d in cards.values())
        nxt = next((w for w in waves if not all(merged(i.upper()) for i in re.findall(r'· (E\d+(?:-S\d+)?)', w.split(' -- ')[0]))), None)
        plan = (pd, changed, nxt)
    rank = lambda p, d: (v(d, 'priority') or 'P9', -idle(p, d))
    opn = {p: d for p, d in cards.items() if v(d, 'status') != 'done'}
    cyc = lambda a, b: {pr: sorted((day(h(p)[b]) - (day(h(p)[a]) if a != 'created' else opened(p, d))).days
                                   for p, d in leaf.items() if bug(d) and h(p).get(b) and (a == 'created' or h(p).get(a))
                                   and h(p).get('added_stage') not in ('Live', 'Checked') and (pr == '' or v(d, 'priority') == pr))
                        for pr in ('', 'P1', 'P2', 'P3')}
    return dict(T=T, src=src, first=first, total=len(leaf), open=len(op), rows=rows,
                flight=flight, next_bugs=next_bugs, plan=plan, can=can,
                waiting=sorted((p for p, d in opn.items() if R.waiting(d)), key=lambda p: rank(p, opn[p])),
                held=sorted((p for p, d in opn.items() if R.warn(d) and not R.waiting(d)), key=lambda p: rank(p, opn[p])),  # waiting: listed there
                lane_idle=[p for p in flight['Now fixing'] if idle(p, op[p]) >= LANE],  # lanes work in hours: idle days = it stopped
                stalled=[p for p in flight['Other work'] if idle(p, op[p]) >= STALL],
                live_old=[p for p in flight['Live, to check'] if idle(p, op[p]) >= STALL],
                checked_open=[p for p, d in op.items() if v(d, 'stage') == 'Checked'],
                epics=sorted(((e, sum(v(leaf[p], 'status') == 'done' for p in kids(e)), len(kids(e))) for e in epics if kids(e)),
                             key=lambda x: (-(x[2] - x[1]), x[0])),
                r2l=cyc('created', 'live'), l2c=cyc('live', 'checked'),
                cards=cards, idle=lambda p: idle(p, cards[p]), title=lambda p: title(cards[p]), epic_cards=epics)

def render(f, proj, needs_only=False):
    c, idle, title, T = f['cards'], f['idle'], f['title'], f['T']
    cut = lambda s, n: s if len(s) <= n else s[:n - 1] + '…'
    cid = lambda p: v(c[p], 'id')
    name = lambda p, n: cid(p) + (f' · {cut(title(p), n)}' if title(p) else '')
    ids = lambda ps: ', '.join(map(cid, ps[:TOP])) + (f' +{len(ps) - TOP} more' if len(ps) > TOP else '')
    since = f" since {f['first']}" if f['first'] else ''
    out = [f"BOARD STATUS — {proj} · {T}",
           f"{f['total']} cards: {f['open']} open, {f['total'] - f['open']} done · dates from {f['src']}{since}", '', 'IN FLIGHT']
    for k, ps in f['flight'].items():
        out.append(f"  {k:<15}{len(ps):>4}  " + (f"{ids(ps)} · oldest idle {idle(ps[0])}d" if ps else '—'))
    out += ['', 'UP NEXT']
    out.append('  Next bug       ' + ('; '.join(name(p, 60) for p in f['next_bugs']) or '—'))
    if f['plan']:
        pd, changed, nxt = f['plan']
        out.append(f"  PLAN.md        {pd or 'undated'}" + (f" · stale: {changed} candidate cards new or changed since" if changed else ' · current'))
        out.append(f"                 next wave: {cut(nxt, 80)}" if nxt else '                 every wave is merged')
    else: out.append('  PLAN.md        none (run /backlog-it plan)')
    for i, p in enumerate(f['can'][:TOP]):
        d = c[p]
        out.append(f"  {'Can start' if not i else '':<15}{name(p, 52)} · {v(d, 'priority')} {v(d, 'size') or '—'}")
    out += [f"  {'':<15}+{len(f['can']) - TOP} more"] * (len(f['can']) > TOP) or ([] if f['can'] else ['  Can start      —'])
    out += ['', f"BURN-DOWN  (cards per week{', history' + since if since else ''})", '  week to   opened  closed    net   open']
    out += [f"  {e.strftime('%m-%d'):<9}{o:>7}{cl:>8}{o - cl:>+7}{left:>7}" for e, o, cl, left in f['rows']]
    out.append('  Forecast: ' + forecast([(o, cl) for _, o, cl, _ in f['rows']], f['open'], T))
    needs = ['NEEDS YOU']
    needs.append(f"  Waiting on you ({len(f['waiting'])})" + ('' if f['waiting'] else ': nothing'))
    needs += [f"    {cid(p)} · {cut(v(c[p], 'decision') or '(question not on card -- add `decision:`)', 70)} · idle {idle(p)}d" for p in f['waiting'][:TOP]]
    needs += [f"    +{len(f['waiting']) - TOP} more (BOARD.md lists all)"] * (len(f['waiting']) > TOP)
    p1 = [p for p in f['held'] if v(c[p], 'priority') == 'P1']  # every P1, oldest first: none may drop out of sight
    needs.append(f"  Held, high-stakes ({len(f['held'])})" + ('' if f['held'] else ': none'))
    needs += [f"    ⚠️ {name(p, 60)} · P1 · idle {idle(p)}d" for p in p1]
    needs += [f"    P2/P3 held: {len(f['held']) - len(p1)} (⚠️ on BOARD.md)"] * (len(f['held']) > len(p1))
    if needs_only: return '\n'.join(needs)
    out += [''] + needs
    drift = [(f'Now fixing, idle {LANE}d+', f['lane_idle'], ' · lane stopped? it should hand the card back'),
             (f'Stalled (idle {STALL}d+)', f['stalled'], ''), (f'Live, idle {STALL}d+', f['live_old'], ''), ('Checked, not closed', f['checked_open'], '')]
    out += ['', 'DRIFT'] + [f"  {k:<22}{len(ps):>3}  {ids(ps)}{hint}" for k, ps, hint in drift if ps]
    if f['plan'] and f['plan'][1]: out.append(f"  PLAN.md is stale       dispatch re-plans first, or falls back to the default order")
    if out[-1] == 'DRIFT': out.append('  none')
    out += ['', f"EPICS  (most open first)"]
    for e, dn, tot in f['epics'][:TOP]:
        ep = f['epic_cards'][e]; n = round(20 * dn / tot)
        out.append(f"  {v(ep, 'id'):<5}{cut(v(ep, 'title').strip(chr(34)), 30):<31}{'█' * n}{'░' * (20 - n)} {dn}/{tot}")
    out += [f"  +{len(f['epics']) - TOP} more epics"] * (len(f['epics']) > TOP)
    out += ['', 'CYCLE TIME  (median days, bugs, transitions seen in git)']
    for k, m in (('Reported → Live', f['r2l']), ('Live → Checked', f['l2c'])):
        med = lambda xs: f'{statistics.median(xs):g} (n={len(xs)})' if xs else '—'
        out.append(f"  {k:<17}{med(m[''])} · " + ' · '.join(f'{pr} {med(m[pr])}' for pr in ('P1', 'P2', 'P3')))
    return '\n'.join(out)

def self_test():
    import tempfile
    T = datetime.date.today(); d = lambda n: str(T - D(days=n))
    with tempfile.TemporaryDirectory() as t:
        os.makedirs(f'{t}/items/EPIC-01-bugs/stories')
        git = lambda *a, when=None: subprocess.run(['git', '-C', t, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false',
                                                   '-c', 'core.hooksPath=/dev/null', *a], check=True, capture_output=True,
                                                  env=dict(os.environ, GIT_AUTHOR_DATE=f'{when}T12:00:00', GIT_COMMITTER_DATE=f'{when}T12:00:00'))
        def card(name, when, **kv):
            open(f'{t}/items/EPIC-01-bugs/{name}', 'w').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
            git('add', '-A', when=when); git('commit', '-qm', name, when=when)
        git('init', '-q')
        bug = dict(type='breakfix', priority='P2', status='in-progress')
        card('epic.md', d(30), id='E01', title='Bugs', type='epic', status='in-progress')
        card('stories/S6.md', d(25), id='E01-S6', title='Old story', type='story', status='in-progress', created=d(25), updated=d(25))
        card('stories/S9.md', d(20), id='E01-S9', title='Imported', type='breakfix', status='done', stage='Checked', created=d(45), updated=d(40))
        card('stories/S1.md', d(20), id='E01-S1', **bug, stage='Reported', created=d(20))
        card('stories/S1.md', d(16), id='E01-S1', **bug, stage='Live', created=d(20))
        card('stories/S2.md', d(12), id='E01-S2', **dict(bug, priority='P1'), stage='Reported', created=d(12))
        card('stories/S14.md', d(10), id='E01-S14', title='Seeded', type='breakfix', status='done', stage='Checked', created=d(10), updated=d(10))  # entered git done, like a seed
        card('stories/S1.md', d(10), id='E01-S1', **dict(bug, status='done'), stage='Checked', created=d(20))
        card('stories/S2.md', d(9), id='E01-S2', **dict(bug, priority='P1'), stage='Live', created=d(12))
        card('stories/S12.md', d(8), id='E01-S12', **bug, stage='Live', created=d(40))  # entered git already Live: no Reported->Live seen
        card('stories/S12.md', d(7), id='E01-S12', **dict(bug, status='done'), stage='Checked', created=d(40))
        card('stories/S10.md', d(6), id='E01-S10', title='Quick one', type='story', status='backlog', created=d(6))
        card('stories/S7.md', d(5), id='E01-S7', **bug, stage='Checked', created=d(5))
        card('stories/S10.md', d(4), id='E01-S10', title='Quick one', type='story', status='done', created=d(6), updated=d(4))
        card('stories/S16.md', d(2), id='E01-S16', title='A story at a bug stage', type='story', status='in-progress', stage='Live', created=d(2))
        card('stories/S8.md', d(3), id='E01-S8', title='Next story', type='story', status='backlog', priority='P2', created=d(3), updated=d(3))
        card('stories/S11.md', d(3), id='E01-S11', title='Waits on S2', type='story', status='backlog', priority='P1', dependsOn='[E01-S2]', created=d(3))
        card('stories/S17.md', d(3), id='E01-S17', **bug, stage='Reported', created=d(3))     # Now fixing, idle 3d: lane stopped?
        card('stories/S18.md', d(1), id='E01-S18', **bug, stage='Cause found', created=d(1))  # Now fixing, idle 1d: fine
        card('stories/S19.md', d(5), id='E01-S19', **bug, stage='Reported', created=d(5))
        card('stories/S20.md', d(1), id='E01-S20', **dict(bug, status='backlog'), stage='Reported', stakes='critical', created=d(1))  # held P2: counted
        card('stories/S21.md', d(1), id='E01-S21', **dict(bug, status='backlog', priority='P1'), stage='Reported', stakes='critical', decision='Ship it?', created=d(1))  # held + waiting: listed once
        for n in range(30, 36):  # six old held P1s: with S4 that's 7 -- the list must not stop at 5
            card(f'stories/S{n}.md', d(30), id=f'E01-S{n}', type='story', status='blocked', priority='P1', stakes='critical', created=d(40))
        card('stories/S3.md', d(2), id='E01-S3', **dict(bug, status='backlog'), stage='Reported', decision='Retry, or refile?', created=d(2))
        card('stories/S4.md', d(2), id='E01-S4', **dict(bug, status='backlog', priority='P1'), stage='Reported', stakes='critical', created=d(2))
        card('stories/S5.md', d(1), id='E01-S5', **dict(bug, status='backlog', priority='P3'), stage='Reported', created=d(1))
        open(f'{t}/PLAN.md', 'w').write(f'# Run Plan -- {d(3)}  (scope: all)\n\n## Waves\n1. **solo** · E01-S1 · done -- unblocks E01-S8\n2. **solo** · E01-S8 · next\n\n## Held\n')
        git('mv', 'items/EPIC-01-bugs/stories/S1.md', 'items/EPIC-01-bugs/stories/S1-moved.md', when=d(0)); git('commit', '-qm', 'mv', when=d(0))
        card('stories/S1.md', d(0), id='E01-S15', **dict(bug, status='backlog', priority='P3'), stage='Reported', created=d(0))  # new card, S1's old path
        open(f'{t}/items/EPIC-01-bugs/stories/S19.md', 'w').write(f'---\nid: E01-S19\ntype: breakfix\nstatus: in-progress\nstage: Cause found\ncreated: {d(5)}\nupdated: {d(0)}\n---\n')  # written, not committed: busy
        f = facts(t, T)
        ids = lambda ps: [v(f['cards'][p], 'id') for p in ps]
        rows = [r[1:] for r in f['rows']]
        # W0: opened S3 S4 S5 S7 S8 S10 S11 S15 S16 S17 S18 S19 S20 S21, closed S10 · W1: S2 / S1 (the move doesn't reset it), S12 · W2: S1 · W3: S6.
        # S9 and S14 entered git already done: neither opened nor closed here.
        assert rows == [(14, 1, 21), (1, 2, 8), (1, 0, 9), (1, 0, 8)], rows  # S30-S35: open since before the window
        assert set(ids(f['flight']['Live, to check'])) == {'E01-S2', 'E01-S16'} and ids(f['flight']['Other work']) == ['E01-S6'], f['flight']
        b = R.render(t, 't')  # the report and BOARD.md agree on every status line
        for k in ('Now fixing', 'Shipping', 'Live, to check'):
            assert set(re.search(rf'\*\*{k}:\*\* (.*)', b).group(1).split(', ')) - {'—'} == {i.split('-')[-1] for i in ids(f['flight'][k])}, k
        assert ids(f['next_bugs']) == ['E01-S5'], ids(f['next_bugs'])  # S4 held, S3 waiting
        assert ids(f['can']) == ['E01-S8'] and ids(f['waiting']) == ['E01-S21', 'E01-S3'] and ids(f['held'])[-1] == 'E01-S20' and len(f['held']) == 8
        assert ids(f['lane_idle']) == ['E01-S17'] and set(ids(f['flight']['Now fixing'])) == {'E01-S17', 'E01-S18', 'E01-S19'}, f['lane_idle']  # S19: newer updated: wins
        assert ids(f['stalled']) == ['E01-S6'] and ids(f['checked_open']) == ['E01-S7'], (f['stalled'], f['checked_open'])
        # stale: candidates S3 S4 S5 S15 changed after the plan, S11 isn't in it; S8 changed that same day; in-flight S16 doesn't count
        assert f['plan'][1] == 7 and f['plan'][2].startswith('2.'), f['plan']  # + S20 S21
        assert f['r2l'][''] == [3, 4] and f['r2l']['P1'] == [3] and f['l2c'][''] == [6], (f['r2l'], f['l2c'])  # S7 entered at Checked
        n = render(f, 't', needs_only=True)  # dispatch's closing list: every held P1 shown, the rest counted, nothing twice
        assert n.startswith('NEEDS YOU') and 'BURN-DOWN' not in n and '⚠️ E01-S4' in n and n.count('\n    ⚠️ ') == 7 and 'P2/P3 held: 1' in n and n.count('E01-S21') == 1, n
        assert 'growing +3.5/wk' in render(f, 't') and 'lane stopped?' in render(f, 't') and '█' in render(f, 't')
        assert len(facts(t, T - D(days=15))['rows']) == 3  # no week that ends before the history starts
        assert forecast([(1, 3), (1, 3)], 8, T).startswith('shrinking -2.0/wk: clear in ~4 wks'), forecast([(1, 3), (1, 3)], 8, T)
        assert forecast([], 0, T) == 'nothing open' and forecast([], 3, T) == 'no full week of history yet'
    print('status self-test: OK')

if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']: self_test(); sys.exit(0)
    proj = None
    if '--project' in args:
        i = args.index('--project')
        if i + 1 >= len(args): sys.exit('status: --project needs a name')
        proj = args[i + 1]; del args[i:i + 2]
    needs = '--needs-you' in args; args = [a for a in args if a != '--needs-you']  # dispatch's closing list
    B = os.path.abspath(os.path.expanduser(args[0] if args else os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'status: no items/ folder in {B}')
    if not proj:
        parent = os.path.dirname(B)
        if os.path.basename(parent) == '.claude': parent = os.path.dirname(parent)
        proj = open(f'{B}/.project').read().strip() if os.path.exists(f'{B}/.project') else os.path.basename(parent)
    print(render(facts(B), proj, needs_only=needs))
