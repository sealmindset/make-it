#!/usr/bin/env python3
"""Check a /backlog-it run plan (the AI pass's JSON) against the board's hard rules.

Usage: check-plan.py <board> <plan.json> [--lane-cap N] [--serial a,b] [--partial]
       check-plan.py --self-test

The AI picks modes and order; this script is the gate. It prints one line per violation and
exits 1 if there are any -- then nothing is written. Rules:
  - every id is used once, with a known mode; a card in a wave is a candidate (status backlog,
    ready, or designing -- in-progress, blocked, and done cards are context, not candidates)
  - waves run in list order (the "wave" field is ignored); a dispatch-it wave holds 3..lane_cap
    cards and nothing else; any other wave holds exactly one card (only dispatch-it runs side by
    side)
  - cards in one dispatch-it wave share no files, no data, no serial category, have no
    conflictsWith between them, and each names its files as repo-relative paths (unknown or
    absolute files = assume overlap; "src/*" covers src/)
  - a high-stakes card (stakes: critical) is held, never in a wave
  - every unfinished dependsOn is planned in an earlier wave
  - a spike names its question and timebox (a not-yet-filed spike says "proposed": true);
    a subagent-it card lists 3+ plan tasks
  - every candidate leaf card is planned, held, or skipped (unless --partial)
"""
import glob, json, os, re, sys, tempfile

MODES = {'solo', 'spike', 'subagent-it', 'dispatch-it'}
CANDIDATE = {'backlog', 'ready', 'designing'}


def fm(p):
    m = re.match(r'---\n(.*?)\n---', open(p).read(), re.S)
    return {k.strip(): v.strip() for k, v in (l.split(':', 1) for l in m.group(1).splitlines() if ':' in l)} if m else {}


def ids(s):  # "[E01-S1, E02]" or "E63-S148" -> ['E01-S1', 'E02']
    return [x.strip().upper() for x in s.strip('[] ').split(',') if x.strip()]


def norm(p):  # "./src/*.ts" -> "src"; "" stands for the whole repo
    p = os.path.normpath(p.split('*')[0] or '.')
    return '' if p == '.' else p


def overlap(a, b):  # same path, or one is a folder holding the other
    a, b = norm(a), norm(b)
    return a == b or not a or not b or a.startswith(b + '/') or b.startswith(a + '/')


def check(board, plan, lane_cap=3, serial=(), partial=False):
    cards = {}
    for p in glob.glob(f'{board}/items/*/epic.md') + glob.glob(f'{board}/items/*/stories/*.md'):
        d = fm(p)
        if d.get('id'): cards[d['id'].upper()] = d
    is_open = lambda i: i in cards and cards[i].get('status') != 'done'
    errs, seen, wave_of = [], set(), {}

    waves = list(enumerate(plan.get('waves', []), 1))
    for n, w in waves:
        for it in w.get('items', []):
            wave_of[it.get('id', '').upper()] = n
    for n, w in waves:
        items = w.get('items', [])
        modes = {it.get('mode') for it in items}
        if 'dispatch-it' in modes:
            if modes != {'dispatch-it'}: errs.append(f'wave {n}: dispatch-it shares the wave with other modes')
            if not 3 <= len(items) <= lane_cap: errs.append(f'wave {n}: dispatch-it needs 3..{lane_cap} cards, has {len(items)}')
            for i, a in enumerate(items):
                if not a.get('files'): errs.append(f"wave {n}: {a.get('id')} names no files -- assume overlap")
                for f in a.get('files', []):
                    if os.path.isabs(f): errs.append(f"wave {n}: {a.get('id')} file {f} is absolute -- use repo-relative paths")
                for b in items[i + 1:]:
                    A, Bc = cards.get(a.get('id', '').upper(), {}), cards.get(b.get('id', '').upper(), {})
                    if any(overlap(x, y) for x in a.get('files', []) for y in b.get('files', [])):
                        errs.append(f"wave {n}: {a['id']} and {b['id']} share files")
                    if set(a.get('data', [])) & set(b.get('data', [])):
                        errs.append(f"wave {n}: {a['id']} and {b['id']} share data")
                    if A.get('category') and A.get('category') == Bc.get('category') and A['category'] in serial:
                        errs.append(f"wave {n}: {a['id']} and {b['id']} are both serial category {A['category']}")
                    if b['id'].upper() in ids(A.get('conflictsWith', '')) or a['id'].upper() in ids(Bc.get('conflictsWith', '')):
                        errs.append(f"wave {n}: {a['id']} and {b['id']} conflict")
        elif len(items) != 1:
            errs.append(f'wave {n}: a {"/".join(sorted(m for m in modes if m)) or "?"} wave holds exactly one card, has {len(items)}')
        for it in items:
            i, mode = it.get('id', '').upper(), it.get('mode')
            if i in seen: errs.append(f'{i}: planned twice')
            seen.add(i)
            if mode == 'spike' and it.get('proposed'):  # filed by `plan --apply`, not a card yet
                if i in cards: errs.append(f'{i}: proposed spike id already exists on the board')
                if not ((it.get('spike') or {}).get('question') and (it.get('spike') or {}).get('timebox')):
                    errs.append(f'{i}: spike needs a question and a timebox')
                continue
            if not is_open(i): errs.append(f'{i}: not an open card on the board'); continue
            if cards[i].get('status') not in CANDIDATE: errs.append(f"{i}: already {cards[i].get('status')} -- not a candidate"); continue
            if mode not in MODES: errs.append(f'{i}: unknown mode {mode!r}')
            if cards[i].get('stakes') == 'critical': errs.append(f'{i}: high-stakes -- hold it, never put it in a wave')
            for d in ids(cards[i].get('dependsOn', '')):
                if is_open(d) and not (isinstance(wave_of.get(d), int) and wave_of[d] < n):
                    errs.append(f'{i}: depends on {d}, which is not planned in an earlier wave')
            if mode == 'spike' and not ((it.get('spike') or {}).get('question') and (it.get('spike') or {}).get('timebox')):
                errs.append(f'{i}: spike needs a question and a timebox')
            if mode == 'subagent-it' and len(it.get('plan_tasks') or []) < 3:
                errs.append(f'{i}: subagent-it needs 3+ plan tasks')

    for key in ('held', 'skipped'):
        for it in plan.get(key, []):
            i = it.get('id', '').upper()
            if i in seen: errs.append(f'{i}: planned twice')
            seen.add(i)
    if not partial:
        parents = {c.get('parent', '').upper() for c in cards.values() if c.get('status') != 'done'}
        for i in sorted(cards):
            if cards[i].get('status') in CANDIDATE and i not in parents and i not in seen:
                errs.append(f'{i}: candidate card not planned, held, or skipped')
    return errs


def self_test():
    with tempfile.TemporaryDirectory() as b:
        os.makedirs(f'{b}/items/EPIC-01-x/stories')
        def card(path, **kv):
            open(f'{b}/items/EPIC-01-x/{path}', 'w').write('---\n' + ''.join(f'{k}: {v}\n' for k, v in kv.items()) + '---\n')
        card('epic.md', id='E01', status='in-progress')
        for n in (1, 2, 3): card(f'stories/S{n}.md', id=f'E01-S{n}', status='backlog', parent='E01', category='ui')
        card('stories/S4.md', id='E01-S4', status='backlog', parent='E01', stakes='critical')
        card('stories/S5.md', id='E01-S5', status='backlog', parent='E01', dependsOn='[E01-S1]')
        D = lambda i, *f: {'id': i, 'mode': 'dispatch-it', 'files': list(f)}
        good = {'waves': [{'wave': 1, 'items': [D('E01-S1', 'a.py'), D('E01-S2', 'b.py'), D('E01-S3', 'c/')]},
                          {'wave': 2, 'items': [{'id': 'E01-S5', 'mode': 'solo'}]}],
                'held': [{'id': 'E01-S4', 'why': 'high-stakes'}]}
        assert check(b, good) == [], check(b, good)
        # a planted shared-file pair in one dispatch wave is caught (folder holds file, too)
        bad = json.loads(json.dumps(good)); bad['waves'][0]['items'][2]['files'] = ['a.py']
        assert any('E01-S1 and E01-S3 share files' in e for e in check(b, bad))
        bad['waves'][0]['items'][2]['files'] = ['c/'];  bad['waves'][0]['items'][1]['files'] = ['c/x.py']
        assert any('share files' in e for e in check(b, bad))
        # serial category, unknown files, high-stakes in a wave, dependsOn order, coverage
        assert any('serial' in e for e in check(b, good, serial=('ui',)))
        bad = json.loads(json.dumps(good)); bad['waves'][0]['items'][0]['files'] = []
        assert any('names no files' in e for e in check(b, bad))
        bad = json.loads(json.dumps(good)); bad['held'] = []; bad['waves'].append({'wave': 3, 'items': [{'id': 'E01-S4', 'mode': 'solo'}]})
        assert any('high-stakes' in e for e in check(b, bad))
        bad = json.loads(json.dumps(good)); bad['waves'].reverse()  # list order rules, not the field
        assert any('depends on E01-S1' in e for e in check(b, bad))
        # path spellings that name the same file, absolute paths, globs
        for x, y in (('./a.py', 'a.py'), ('c/*', 'c/x.py'), ('*', 'b.py')):
            bad = json.loads(json.dumps(good)); bad['waves'][0]['items'][0]['files'] = [x]; bad['waves'][0]['items'][1]['files'] = [y]
            assert any('share files' in e for e in check(b, bad)), (x, y)
        bad = json.loads(json.dumps(good)); bad['waves'][0]['items'][0]['files'] = ['/repo/a.py']
        assert any('absolute' in e for e in check(b, bad))
        # a proposed spike passes without being a card; one missing its timebox does not
        ok = json.loads(json.dumps(good)); ok['waves'].insert(1, {'wave': 2, 'items': [{'id': 'E01-S9', 'mode': 'spike', 'proposed': True, 'spike': {'question': 'q', 'timebox': '1h'}}]})
        assert check(b, ok) == [], check(b, ok)
        reuse = json.loads(json.dumps(ok)); reuse['waves'][1]['items'][0]['id'] = 'E01-S2'
        assert any('already exists' in e for e in check(b, reuse))
        ok['waves'][1]['items'][0]['spike'] = {'question': 'q'}
        assert any('timebox' in e for e in check(b, ok))
        bad = json.loads(json.dumps(good)); bad['held'] = []
        assert any('E01-S4: candidate card not planned' in e for e in check(b, bad))
        assert check(b, bad, partial=True) == []
        # an in-progress card is context: not required in the plan, refused in a wave
        card('stories/S6.md', id='E01-S6', status='in-progress', parent='E01')
        assert check(b, good) == [], check(b, good)
        bad = json.loads(json.dumps(good)); bad['waves'].append({'wave': 3, 'items': [{'id': 'E01-S6', 'mode': 'solo'}]})
        assert any('E01-S6: already in-progress' in e for e in check(b, bad))
        # wave shape: two solos in one wave, a 2-card dispatch wave
        bad = {'waves': [{'wave': 1, 'items': [{'id': 'E01-S1', 'mode': 'solo'}, {'id': 'E01-S2', 'mode': 'solo'}]}]}
        assert any('exactly one card' in e for e in check(b, bad, partial=True))
        bad = {'waves': [{'wave': 1, 'items': [D('E01-S1', 'a'), D('E01-S2', 'b')]}]}
        assert any('needs 3..3' in e for e in check(b, bad, partial=True))
    print('check-plan self-test: OK')


if __name__ == '__main__':
    a = sys.argv[1:]
    if a == ['--self-test']: self_test(); sys.exit(0)
    def opt(name, default):
        if name in a:
            i = a.index(name); val = a[i + 1]; del a[i:i + 2]; return val
        return default
    lane_cap = int(opt('--lane-cap', 3)); serial = tuple(x for x in opt('--serial', '').split(',') if x)
    partial = '--partial' in a; a = [x for x in a if x != '--partial']
    if len(a) != 2: sys.exit(__doc__)
    errs = check(os.path.expanduser(a[0]), json.load(open(a[1])), lane_cap, serial, partial)
    print('\n'.join(errs) if errs else 'plan OK')
    sys.exit(1 if errs else 0)
