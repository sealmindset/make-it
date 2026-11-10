#!/usr/bin/env python3
"""Which cards a /backlog-it plan (or groom) covers: the filter's cards and, with --with-deps, the
chain of open cards they wait on -- across epics.

Usage: scope.py <board> [<filter>] [--with-deps]
       scope.py --self-test

<filter>, case-insensitive: a card id (that card if it's a leaf, else the open cards under it -- an
epic id is a card id), a status, a priority (P1..P3), or a category. None: every open card.
What a card waits on is the board's one rule (regen-board.needs): its own dependsOn and every
ancestor's, an id with children standing for its open cards. Only upstream is followed -- what the
filter's cards wait on, never what waits on them -- and conflictsWith is not a dependency.

Prints JSON for the plan's route call and its gate (check-plan.py --scope):
  filter, with_deps
  in_filter  the candidate leaf cards the filter names (status backlog, ready, or designing)
  pulled_in  [{id, title, for, needed_by, gate}] with --with-deps: candidates outside the filter
             that a filter card waits on, directly or down the chain. `for` = the filter cards it
             serves; `needed_by` = the cards that wait on it directly; `gate` = "high-stakes" or
             "waits on you" when it can't go in a wave (then the cards that need it are skipped)
  outside    [{id, for}] without --with-deps: open cards outside the filter that filter cards wait
             on -- those filter cards are skipped; --with-deps pulls these in
  waits      [{id, status, for}] cards in the chain that can't be planned (in progress or
             blocked): not followed further, and the cards that need them are skipped
  loops      [[id, ...]] cards in scope that wait on each other: skip them, fix their dependsOn
  scope      in_filter + pulled_in ids: every id the plan must place in a wave, hold, or skip
  notes      plain warnings: a filter that matches nothing to plan, a link to an id not on this board
Exit 2 when the filter names a card id that isn't on the board.
"""
import importlib.util, json, os, re, subprocess, sys, tempfile

_bin = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(_bin, 'regen-board.py'))
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
v = R.v
CANDIDATE = ('backlog', 'ready', 'designing')
ID = re.compile(r'E\d+(?:-S\d+)*', re.I)


def key(i): return [int(n) for n in re.findall(r'\d+', i)] or [0]  # E2-S10 after E2-S9


def scope(board, flt='', with_deps=False):
    T = R.tree(R.load(board)); byid, kids, up = T
    cand = lambda i: i not in kids and v(byid[i], 'status') in CANDIDATE
    leafs = [i for i in byid if i not in kids]
    f, notes = flt.strip(), []
    if not f: named = leafs
    elif ID.fullmatch(f):
        if f.upper() not in byid: raise LookupError(f'{f.upper()} is not a card on this board')
        named = R.leaves(f.upper(), T)
    elif f.lower() in R.ORDER: named = [i for i in leafs if v(byid[i], 'status') == f.lower()]
    elif re.fullmatch(r'P\d', f, re.I): named = [i for i in leafs if v(byid[i], 'priority').upper() == f.upper()]
    else: named = [i for i in leafs if v(byid[i], 'category').lower() == f.lower()]
    in_filter = sorted({i for i in named if cand(i)}, key=key)
    if f and not in_filter: notes.append(f'nothing to plan: no card in backlog, ready, or designing matches "{f}"')
    if with_deps and not f: notes.append('--with-deps adds nothing without a filter: every open card is already in scope')

    edges, pulled, outside, waits = {}, {}, {}, {}  # edges: card -> the leaves it waits on
    todo, seen, S = list(in_filter), set(in_filter), set(in_filter)
    while todo:
        c = todo.pop(0)
        line, p = [], c
        while p in byid and p not in line: line.append(p); p = up.get(p, '')
        for a in line:
            for d in R.ids(v(byid[a], 'dependsOn')):
                if d not in byid:
                    n = f"{c} depends on {d}{'' if a == c else f' (through {a})'}, which isn't on this board -- it doesn't block (it may live on another board)"
                    if n not in notes: notes.append(n)
        for leaf, _, _ in R.needs(c, T):
            edges.setdefault(c, []).append(leaf)
            if leaf in S: continue
            if not with_deps: outside.setdefault(leaf, set()).add(c); continue
            if v(byid[leaf], 'status') in CANDIDATE:
                pulled.setdefault(leaf, set()).add(c)
                if leaf not in seen: seen.add(leaf); todo.append(leaf)
            else: waits.setdefault(leaf, set()).add(c)

    def reach(r):  # every card r waits on, down the chain
        out, todo = set(), list(edges.get(r, []))
        while todo:
            x = todo.pop()
            if x in out: continue
            out.add(x); todo += edges.get(x, [])
        return out
    R_ = {i: reach(i) for i in seen}
    serves = lambda x: sorted((r for r in in_filter if x in R_[r]), key=key)
    loops, inloop = [], set()
    for i in sorted(seen, key=key):
        if i in inloop: continue
        group = sorted({i} | {j for j in R_[i] if j in seen and i in R_[j]}, key=key)
        if len(group) > 1: loops.append(group); inloop |= set(group)

    gate = lambda d: 'high-stakes' if R.warn(d) else ('waits on you' if R.waiting(d) else '')
    return {
        'filter': f, 'with_deps': with_deps, 'in_filter': in_filter,
        'pulled_in': [{'id': i, 'title': v(byid[i], 'title').strip('"'), 'for': serves(i),
                       'needed_by': sorted(pulled[i], key=key), 'gate': gate(byid[i])} for i in sorted(pulled, key=key)],
        'outside': [{'id': i, 'for': sorted(outside[i], key=key)} for i in sorted(outside, key=key)],
        'waits': [{'id': i, 'status': v(byid[i], 'status'), 'for': serves(i)} for i in sorted(waits, key=key)],
        'loops': loops,
        'scope': in_filter + sorted(pulled, key=key),
        'notes': notes,
    }


def self_test():
    with tempfile.TemporaryDirectory() as b:
        def card(epic, name, **kv):
            os.makedirs(f'{b}/items/{epic}/stories', exist_ok=True)
            open(f'{b}/items/{epic}/{name}', 'w').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
        E = lambda n: f'EPIC-0{n}-x'
        card(E(1), 'epic.md', id='E01', type='epic', status='in-progress')
        card(E(1), 'stories/S1.md', id='E01-S1', status='backlog', parent='E01')
        card(E(1), 'stories/S2.md', id='E01-S2', status='ready', parent='E01', dependsOn='[E02-S1]')
        card(E(1), 'stories/S3.md', id='E01-S3', status='backlog', parent='E01', dependsOn='[e03]')
        card(E(1), 'stories/S4.md', id='E01-S4', status='backlog', parent='E01', dependsOn='[E06]')
        card(E(1), 'stories/S5.md', id='E01-S5', status='designing', parent='E01', dependsOn='[E99-S1]')
        card(E(1), 'stories/S6.md', id='E01-S6', status='done', parent='E01')
        card(E(2), 'epic.md', id='E02', type='epic', status='backlog')
        card(E(2), 'stories/S1.md', id='E02-S1', title='"Orders table"', status='backlog', parent='E02', dependsOn='[E02-S2]')
        card(E(2), 'stories/S2.md', id='E02-S2', status='backlog', parent='E02', stakes='critical')
        card(E(2), 'stories/S3.md', id='E02-S3', status='in-progress', parent='E02')
        card(E(3), 'epic.md', id='E03', type='epic', status='backlog', dependsOn='[E02-S3]')
        card(E(3), 'stories/S1.md', id='E03-S1', status='backlog')  # no parent: its folder's epic, so it inherits E03's dependsOn
        card(E(3), 'stories/S2.md', id='E03-S2', status='done', parent='E03')
        card(E(4), 'epic.md', id='E04', type='epic', status='backlog', dependsOn='[E01-S1]')
        card(E(4), 'stories/S1.md', id='E04-S1', status='backlog', parent='E04', priority='P1', category='Billing')
        card(E(5), 'epic.md', id='E05', type='epic', status='backlog')
        card(E(5), 'stories/S1.md', id='E05-S1', status='backlog', parent='E05', dependsOn='[E05-S2]')
        card(E(5), 'stories/S2.md', id='E05-S2', status='backlog', parent='E05', dependsOn='[E05-S1]', decision='x')
        card(E(6), 'epic.md', id='E06', type='epic', status='backlog')
        card(E(6), 'stories/S1.md', id='E06-S1', status='done', parent='E06')
        card(E(7), 'epic.md', id='E07', type='epic', status='backlog')
        card(E(7), 'stories/S1.md', id='E07-S1', status='backlog', parent='E07', dependsOn='[E01-S2]')

        F = ['E01-S1', 'E01-S2', 'E01-S3', 'E01-S4', 'E01-S5']
        s = scope(b, 'E01')  # without the chain: the cards outside are named, not planned
        assert s['in_filter'] == F and s['scope'] == F and s['pulled_in'] == [] and s['waits'] == [], s
        assert s['outside'] == [{'id': 'E02-S1', 'for': ['E01-S2']}, {'id': 'E03-S1', 'for': ['E01-S3']}], s['outside']
        assert any('E99-S1' in n and "isn't on this board" in n for n in s['notes']), s['notes']
        s = scope(b, 'e01', True)  # the chain, across epics: E02-S1 needs high-stakes E02-S2; E03-S1 inherits E03's link
        assert s['scope'] == F + ['E02-S1', 'E02-S2', 'E03-S1'] and s['outside'] == [], s
        P = {x['id']: x for x in s['pulled_in']}
        assert P['E02-S1'] == {'id': 'E02-S1', 'title': 'Orders table', 'for': ['E01-S2'], 'needed_by': ['E01-S2'], 'gate': ''}, P
        assert P['E02-S2']['for'] == ['E01-S2'] and P['E02-S2']['needed_by'] == ['E02-S1'] and P['E02-S2']['gate'] == 'high-stakes', P
        assert P['E03-S1']['for'] == ['E01-S3'], P  # E01-S3 names the epic E03: its open card
        assert s['waits'] == [{'id': 'E02-S3', 'status': 'in-progress', 'for': ['E01-S3']}], s['waits']  # in progress: not followed
        assert 'E07-S1' not in s['scope'] and 'E06-S1' not in json.dumps(s), s  # upstream only; a finished epic waits on nothing
        s = scope(b, 'E04-S1', True)  # a card id: one story and its chain, which comes through its epic
        assert s['in_filter'] == ['E04-S1'] and s['scope'] == ['E04-S1', 'E01-S1'] and s['pulled_in'][0]['needed_by'] == ['E04-S1'], s
        s = scope(b, 'E05', True)
        assert s['loops'] == [['E05-S1', 'E05-S2']] and s['scope'] == ['E05-S1', 'E05-S2'], s
        s = scope(b, 'E07', True)  # its chain runs through E01-S2 into E02
        assert s['scope'] == ['E07-S1', 'E01-S2', 'E02-S1', 'E02-S2'] and s['pulled_in'][-1]['for'] == ['E07-S1'], s
        assert scope(b, 'p1')['in_filter'] == ['E04-S1'] and scope(b, 'billing')['in_filter'] == ['E04-S1']
        assert scope(b, 'ready')['in_filter'] == ['E01-S2'] and scope(b, 'designing')['in_filter'] == ['E01-S5']
        for f in ('in-progress', 'E01-S6', 'nosuch'):
            s = scope(b, f); assert s['in_filter'] == [] and any('nothing to plan' in n for n in s['notes']), (f, s)
        s = scope(b, '', True)
        assert s['pulled_in'] == [] and 'E07-S1' in s['scope'] and any('adds nothing' in n for n in s['notes']), s
        try: scope(b, 'E42'); raise AssertionError('an unknown id passed')
        except LookupError: pass
        r = subprocess.run([sys.executable, __file__, b, 'E42', '--with-deps'], capture_output=True, text=True)
        assert r.returncode == 2 and 'E42 is not a card' in r.stderr, r
        r = subprocess.run([sys.executable, __file__, b, 'E01', '--with-deps'], capture_output=True, text=True)
        assert r.returncode == 0 and json.loads(r.stdout)['scope'][-1] == 'E03-S1', r
    print('scope self-test: OK')


if __name__ == '__main__':
    a = sys.argv[1:]
    if a == ['--self-test']: self_test(); sys.exit(0)
    wd = '--with-deps' in a; a = [x for x in a if x != '--with-deps']
    if not a or not os.path.isdir(os.path.join(os.path.expanduser(a[0]), 'items')): sys.exit(__doc__)
    try: out = scope(os.path.expanduser(a[0]), ' '.join(a[1:]), wd)  # a category can have spaces
    except LookupError as e: print(f'scope: {e}', file=sys.stderr); sys.exit(2)
    print(json.dumps(out, indent=2))
