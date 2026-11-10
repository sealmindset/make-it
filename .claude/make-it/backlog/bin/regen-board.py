#!/usr/bin/env python3
"""Render <board>/BOARD.md from card frontmatter (items/ only; archive/ is not shown).

Usage: regen-board.py [board_dir] [--project NAME]
       regen-board.py --self-test
  board_dir  defaults to $BACKLOG_DIR, then ./.claude/backlog
  --project  defaults to <board>/.project, then the project folder's name
"""
import datetime, glob, os, re, sys

ORDER = ['in-progress', 'ready', 'blocked', 'designing', 'backlog', 'done']
BIG = 30  # ponytail: an epic past this many cards counts its done cards and groups the rest by category
def fm(p):
    m = re.match(r'---\n(.*?)\n---', open(p).read(), re.S)
    return dict(l.split(':', 1) for l in m.group(1).splitlines() if ':' in l) if m else {}
def v(d, k): return d.get(k, '').strip()
def num(s): return int(re.sub(r'\D', '', v(s, 'id').split('-S')[-1]) or 0)
def chips(d): return (f" [{v(d,'size')}]" if v(d, 'size') else '') + (f" 📌{v(d,'pin')}" if v(d, 'pin') else '') + (f" →{v(d,'mode')}" if v(d, 'mode') else '')
def warn(d): return '⚠️' if v(d, 'stakes') == 'critical' else ''
def load(B):  # card path -> frontmatter, epics first
    return {p: fm(p) for p in glob.glob(f'{B}/items/*/epic.md') + glob.glob(f'{B}/items/*/stories/*.md')}
def waiting(d):  # open and blocked on the human's answer; `stage: Needs decision` is the older form
    return v(d, 'status') != 'done' and bool(v(d, 'decision') or v(d, 'stage') == 'Needs decision')
def ask(d):
    """(question, lines under it): `decision:` (plain context, then the question) and its 2-4 `answers:`
    (`Name -- what it does`, split by `|`), or the gap flagged -- the same shape on BOARD.md and in status."""
    q, opts = v(d, 'decision'), [a.strip() for a in v(d, 'answers').split('|') if a.strip()]
    if not q: return '(question not on card -- add `decision:` and `answers:`)', []
    # ponytail: a word count catches a bare id or a few words, not shorthand ("fold", "apply-day") -- the doctrine bans that
    gap = ['no context -- say in plain words what waits and why'] * (len(re.findall(r'[A-Za-z]{2,}', re.sub(r'#\d+|\b[A-Z]+\d+(?:-S\d+)?\b', ' ', q))) < 6)
    if not opts: gap.append('answers not on card -- add `answers:`')
    elif not 2 <= len(opts) <= 4 or not all(re.search(' (--|—) ', a) for a in opts): gap.append('needs 2-4 answers, each `Name -- what it does`, split by `|`')
    elif any('recommended' in a.lower() and 'against:' not in a.lower() for a in opts): gap.append('the Recommended answer needs `against:` its strongest counter-argument')
    return q, opts + [f"({'; '.join(gap)})"] * bool(gap)
def age(d):
    try: return f" · {max(0, (datetime.date.today() - datetime.date.fromisoformat(v(d, 'updated'))).days)}d"  # UTC can be a day ahead
    except ValueError: return ''
def ids(x): return [i.strip().upper() for i in x.strip('[] ').split(',') if i.strip()]  # "[E01-S1, e02]" -> ['E01-S1', 'E02']
def tree(cards):
    """(id -> card, id -> its child ids, id -> its parent id): what `needs` walks. `cards` is load()'s
    {path: card} or a plain list; with paths, a story with no `parent:` belongs to its folder's epic."""
    items = list(cards.items()) if isinstance(cards, dict) else [('', d) for d in cards]
    epic_of = {os.path.dirname(p): v(d, 'id').upper() for p, d in items if p.endswith('/epic.md')}
    byid, kids, up = {}, {}, {}
    for p, d in items:
        i = v(d, 'id').upper()
        if not i: continue
        byid[i] = d
        par = v(d, 'parent').upper() or (epic_of.get(os.path.dirname(os.path.dirname(p)), '') if '/stories/' in p else '')
        if par and par != i: up[i] = par; kids.setdefault(par, []).append(i)
    return byid, kids, up
def leaves(d, T):  # what waiting on d means: d itself if it's an open leaf, else the open leaf cards under it
    byid, kids, _ = T
    out, todo, seen = [], [d], set()
    while todo:
        c = todo.pop()
        # ponytail: an id not on this board doesn't block -- it may live on another board; a done card is
        # finished even with open children (an epic whose children are all done is finished too)
        if c in seen or c not in byid or v(byid[c], 'status') == 'done': continue
        seen.add(c)
        if c in kids: todo += kids[c]
        else: out.append(c)
    return sorted(out)
def needs(i, T):
    """What card i waits on: [(open leaf, the card whose dependsOn says so, the id it names)]. Its own
    dependsOn and every ancestor's (an epic's dependsOn holds for each card under it); an id with
    children stands for its open leaf cards. A card never waits on itself or its own ancestors."""
    byid, _, up = T
    line, p = [], i.upper()
    while p in byid and p not in line: line.append(p); p = up.get(p, '')
    out, got = [], set()
    for a in line:
        for d in ids(v(byid[a], 'dependsOn')):
            for leaf in [] if d in line else leaves(d, T):
                if leaf not in got and leaf not in line: got.add(leaf); out.append((leaf, a, d))
    return out
def blocked(s, T):  # can't start: high-stakes, waiting on you, or waiting on an unfinished card
    return bool(warn(s)) or waiting(s) or bool(needs(v(s, 'id'), T))
DATED = r'v?(\d{4})[.-](\d{2})[.-](\d{2})(?:[.-]\d+)?'
def due(s, T=None):  # a Live card's check can be done now: no checkAfter, or its date (a date, or a release tag named for it) has come
    # ponytail: a release tag counts as out on the date in its name (v2026.10.17); an undated tag waits -- use a date there
    m = re.fullmatch(DATED, v(s, 'checkAfter'))
    if not v(s, 'checkAfter'): return True
    try: return bool(m) and datetime.date(*map(int, m.groups())) <= (T or datetime.date.today())
    except ValueError: return False  # not a real date (2026-02-30): it waits, and status flags it -- never a crash
def soon(w): return (not re.fullmatch(DATED, w), w.lstrip('vV').replace('-', '.'))  # waits in date order, undated last
def bucket(s):  # which bug-queue status line an open card sits on, if any
    if v(s, 'status') == 'done': return None
    if v(s, 'stage') in ('Reported', 'Cause found'): return 'Now fixing' if v(s, 'status') == 'in-progress' and not waiting(s) else None
    if v(s, 'stage') == 'Live': return 'Live, to check' if due(s) else 'Live, waits'
    return {'Fix ready': 'Shipping'}.get(v(s, 'stage'))
def startable(s, T): return v(s, 'status') == 'backlog' and not blocked(s, T)  # Next up
def next_up(stories, T):
    return next((v(s, 'id').split('-')[-1] for s in sorted(stories, key=lambda s: (v(s, 'priority') or 'P9', num(s)))
                 if v(s, 'type') == 'breakfix' and startable(s, T)), '—')

def render(B, proj):
    L = load(B); CARDS = list(L.values())
    TREE = tree(L)
    out = [f'# BACKLOG BOARD — {proj}', '']
    wait = sorted(filter(waiting, CARDS), key=lambda d: (v(d, 'priority') or 'P9', v(d, 'updated') or '9'))
    if wait:
        out += [f'## Waiting on you ({len(wait)})', '_each card · days since it last changed, then what waits and why, and the answers to pick from_', '']
        for d in wait:
            q, under = ask(d)
            t = v(d, 'title').strip('"')
            out += [f"- {warn(d)}{v(d,'id')}{' · ' * bool(t)}{t}{age(d)}", f'  - {q}'] + [f'    - {x}' for x in under]
        out.append('')
    for ep in sorted(glob.glob(f'{B}/items/*/epic.md')):
        e = fm(ep)
        stories = [fm(s) for s in glob.glob(os.path.join(os.path.dirname(ep), 'stories', '*.md'))]
        stories.sort(key=lambda s: (ORDER.index(v(s, 'status')) if v(s, 'status') in ORDER else 9, num(s)))
        counts = ' · '.join(f'{st} {n}' for st in ORDER if (n := sum(v(s, 'status') == st for s in stories)))
        out += [f"## {warn(e)}{v(e,'id')} · {v(e,'title')}  _[{v(e,'status')}]_{chips(e)}", f'_{counts}_', '']
        if any(v(s, 'type') == 'breakfix' for s in stories):
            # The bug queue status line: Reported -> Cause found -> Fix ready -> Live -> Checked.
            def ids(pred): return ', '.join(v(s, 'id').split('-')[-1] for s in stories if pred(s)) or '—'
            nxt = next_up(stories, TREE)
            waits = sorted({v(s, 'checkAfter') for s in stories if bucket(s) == 'Live, waits'}, key=soon)
            out += [f'**{k}:** ' + ids(lambda s: bucket(s) == k) for k in ('Now fixing', 'Shipping', 'Live, to check')] + [
                    '**Live, waits:** ' + ' · '.join(f"{w} → {ids(lambda s: bucket(s) == 'Live, waits' and v(s, 'checkAfter') == w)}" for w in waits)] * bool(waits) + [
                    '**Next up:** ' + nxt, '']
        big = len(stories) > BIG
        for st in ORDER:
            group = [s for s in stories if v(s, 'status') == st]
            if not group: continue
            out.append(f'### {st} ({len(group)})')
            if big and st == 'done':
                out += [f"_listed by `/backlog-it show {v(e,'id')}`_", '']; continue
            if big: group.sort(key=lambda s: (v(s, 'category') or '~', num(s)))
            cat = None
            for s in group:
                if big and v(s, 'category') != cat:
                    cat = v(s, 'category'); out += ['', f"**{cat or 'uncategorized'}** ({sum(v(x, 'category') == cat for x in group)})"]
                mark = warn(s) + ('⚡' if v(s, 'type') == 'breakfix' else ('🔬' if v(s, 'type') == 'spike' else ''))
                stage = f" — **{v(s,'stage')}**" if v(s, 'stage') and st != 'done' else ''
                out.append(f"- {mark}{v(s,'id')} · {v(s,'title')}{stage}  _[{v(s,'category')}] {v(s,'priority')}_{chips(s)}")
            out.append('')
    return '\n'.join(out)

def main(args):
    if args == ['--self-test']:
        import subprocess, tempfile
        with tempfile.TemporaryDirectory() as t:
            os.makedirs(f'{t}/items/EPIC-01-bugs/stories')
            def card(name, **kv): open(f'{t}/items/EPIC-01-bugs/{name}', 'w').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
            def board(): subprocess.run([sys.executable, __file__, t, '--project', 't'], check=True); return open(f'{t}/BOARD.md').read()
            card('epic.md', id='E01', title='Bugs', status='in-progress')
            card('stories/S1.md', id='E01-S1', status='backlog', type='breakfix', priority='P1', stakes='critical')
            card('stories/S2.md', id='E01-S2', status='backlog', type='breakfix', priority='P1', dependsOn='E01-S4')
            card('stories/S3.md', id='E01-S3', status='backlog', type='breakfix', priority='P2', dependsOn='[E01-S5, E09-S1]')
            card('stories/S4.md', id='E01-S4', status='in-progress', type='breakfix', stage='Cause found')
            card('stories/S5.md', id='E01-S5', status='done', type='breakfix')
            # S1 is high-stakes, S2 waits on in-progress S4; S3's deps are done or not on this board
            assert '**Next up:** S3' in board()
            card('stories/S3.md', id='E01-S3', status='backlog', type='breakfix', priority='P2', dependsOn='[e01-s4]')
            assert '**Next up:** —' in board()
            # Waiting on you: any open card with a decision (or the older stage), skipped by Now fixing / Next up
            # each item answerable cold: the title, plain context + the question, 2-4 named answers -- or the gap flagged
            Q = 'The nightly import skipped 3 rows that failed twice; nothing else waits on them. Retry them, or refile by hand?'
            A = 'Retry -- runs the import again tonight (Recommended; against: a third failure costs another day) | Refile -- you re-enter the 3 rows'
            card('stories/S3.md', id='E01-S3', title='Import skips rows', status='backlog', type='breakfix', priority='P2', decision=Q, answers=A)
            card('stories/S4.md', id='E01-S4', status='in-progress', type='breakfix', stage='Cause found', decision='Narrow fix or wide?')
            card('stories/S6.md', id='E01-S6', status='in-progress', type='breakfix', stage='Needs decision')
            card('stories/S7.md', id='E01-S7', status='backlog', type='story', decision='E68-S7 / #1628 go?', answers=A)
            card('stories/S8.md', id='E01-S8', status='done', type='story', decision='Old question')
            b = board(); item = lambda i: re.search(rf'^- {i}\b.*?\n(?=- |\n)', b, re.M | re.S).group(0)
            assert '## Waiting on you (4)' in b and item('E01-S3') == f'- E01-S3 · Import skips rows\n  - {Q}\n    - {A.split(" | ")[0]}\n    - {A.split(" | ")[1]}\n', b
            assert 'no context' in item('E01-S7') and 'answers not on card' in item('E01-S4') and 'no context' in item('E01-S4'), b  # an id, shorthand
            assert '(question not on card' in item('E01-S6') and 'Old question' not in b, b
            assert '**Now fixing:** —' in b and '**Next up:** —' in b, b
            for bad, gap in (('Retry -- runs it', '2-4 answers'), (A + ' | Wait | Drop -- x', '2-4 answers'), (A + ' | Wait -- x | Drop -- y | Ask -- z', '2-4 answers'), (A.replace('; against:', ','), 'against:'), ('Retry: runs it | Refile: by hand', '2-4 answers')):
                card('stories/S7.md', id='E01-S7', status='backlog', type='story', decision=Q, answers=bad)
                b = board(); assert gap in item('E01-S7'), (bad, b)
            card('stories/S7.md', id='E01-S7', status='backlog', type='story', decision='PR1611 PR897 GH12 INC4 CVE2024 merge?', answers=A)
            b = board(); assert 'no context' in item('E01-S7'), b  # letter-prefixed ids are ids, not words
            for good in (A.replace(' -- ', ' — ', 1), A + ' | Wait -- x | Drop -- y'):  # once present: no gap (an em dash; exactly 4)
                card('stories/S7.md', id='E01-S7', status='backlog', type='story', decision=Q, answers=good)
                b = board(); assert '(' not in item('E01-S7').replace('(Recommended', ''), (good, b)
            card('stories/S3.md', id='E01-S3', title='Import skips rows', status='backlog', type='breakfix', priority='P2')  # answered
            b = board()
            assert '**Next up:** S3' in b and 'Import skips rows' not in b.split('## E01')[0] and '## Waiting on you (3)' in b, b
            card('stories/S9.md', id='E01-S9', status='backlog', type='story', priority='P1')  # Next up is a bug
            assert '**Next up:** S3' in board()
            # A big epic (over 30 cards): done cards as a count, open cards grouped by category; small epics unchanged
            os.makedirs(f'{t}/items/EPIC-02-big/stories')
            open(f'{t}/items/EPIC-02-big/epic.md', 'w').write('---\nid: E02\ntitle: Big\nstatus: in-progress\n---\n')
            for n in range(1, 34):
                kv = dict(id=f'E02-S{n}', title=f'T{n}', status='done' if n < 3 else 'backlog', category='zeta' if n % 2 else 'alpha')
                open(f'{t}/items/EPIC-02-big/stories/S{n}.md', 'w').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
            b = board(); big = b.split('## E02')[1]
            assert '### done (2)\n_listed by `/backlog-it show E02`_' in big and 'E02-S1 ·' not in big and 'E02-S2 ·' not in big, big
            assert big.index('**alpha** (15)') < big.index('- E02-S4 ·') < big.index('**zeta** (16)') < big.index('- E02-S3 ·'), big
            assert '\n\n**zeta** (16)\n- ' in big, 'a heading right after a list item renders glued to it'
            assert not re.search(r'^\*\*[^*:]+\*\* \(\d+\)$', b.split('## E02')[0], re.M), 'small epic grouped'
            # Live splits by checkAfter: a date or a dated release tag that has come is due; later or undated waits
            card('stories/S20.md', id='E01-S20', status='in-progress', type='breakfix', stage='Live', checkAfter='2099-01-01')
            card('stories/S21.md', id='E01-S21', status='in-progress', type='breakfix', stage='Live', checkAfter='v2020.01.01')
            card('stories/S22.md', id='E01-S22', status='in-progress', type='breakfix', stage='Live', checkAfter='v1.41.0')
            card('stories/S23.md', id='E01-S23', status='in-progress', type='breakfix', stage='Live')
            b = board()
            assert re.search(r'\*\*Live, to check:\*\* S21, S23\n', b) and '**Live, waits:** 2099-01-01 → S20 · v1.41.0 → S22\n' in b, b
            card('stories/S24.md', id='E01-S24', status='in-progress', type='breakfix', stage='Live', checkAfter=str(datetime.date.today()))  # due on the day
            card('stories/S25.md', id='E01-S25', status='in-progress', type='breakfix', stage='Live', checkAfter='2026-02-30')  # not a date: waits, no crash
            card('stories/S26.md', id='E01-S26', status='in-progress', type='breakfix', stage='Live', checkAfter='v2098.12.31')
            b = board()
            assert re.search(r'\*\*Live, to check:\*\* S21, S23, S24\n', b), b
            assert '**Live, waits:** 2026-02-30 → S25 · v2098.12.31 → S26 · 2099-01-01 → S20 · v1.41.0 → S22\n' in b, b  # in date order
            # what a card waits on: an id with children means its open cards; an epic's dependsOn holds for every card under it
            os.makedirs(f'{t}/items/EPIC-03-later/stories')
            open(f'{t}/items/EPIC-03-later/epic.md', 'w').write('---\nid: E03\nstatus: backlog\n---\n')
            later = lambda n, st: open(f'{t}/items/EPIC-03-later/stories/S{n}.md', 'w').write(f'---\nid: E03-S{n}\nstatus: {st}\nparent: E03\n---\n')
            later(1, 'done')
            card('stories/S3.md', id='E01-S3', title='Import skips rows', status='backlog', type='breakfix', priority='P2', dependsOn='[E03]')
            assert '**Next up:** S3' in board()  # an open epic whose cards are all done is finished
            later(2, 'backlog'); assert '**Next up:** —' in board()  # now it has an open card to wait on
            later(2, 'done'); card('stories/S3.md', id='E01-S3', title='Import skips rows', status='backlog', type='breakfix', priority='P2')
            assert '**Next up:** S3' in board()
            later(3, 'in-progress'); card('epic.md', id='E01', title='Bugs', status='in-progress', dependsOn='[E03-S3]')
            assert '**Next up:** —' in board()  # S3 inherits its epic's dependsOn
        # needs(), directly: (leaf, whose dependsOn, the id it names); never itself or its ancestors; a parent loop ends
        C = lambda i, **kv: dict(id=i, status=kv.pop('status', 'backlog'), **kv)
        T = tree([C('E01', dependsOn='[E01-S1, E02]'), C('E01-S1', parent='E01'), C('E01-S2', parent='E01', dependsOn='E01'),
                  C('E02'), C('E02-S1', parent='E02'), C('E02-S2', parent='E02', status='done'), C('E02-S3', parent='E02', dependsOn='[E03-S1]'),
                  C('E02-S4', parent='E02-S3'), C('E03-S1', parent='E03-S2'), C('E03-S2', parent='E03-S1'), C('E04', status='done'), C('E04-S1', parent='E04')])
        assert needs('E01-S1', T) == [('E02-S1', 'E01', 'E02'), ('E02-S4', 'E01', 'E02')], needs('E01-S1', T)  # E02-S3 is a container: its open leaf
        assert needs('e01-s2', T) == [('E01-S1', 'E01', 'E01-S1'), ('E02-S1', 'E01', 'E02'), ('E02-S4', 'E01', 'E02')], needs('E01-S2', T)  # E01 named: its own ancestor
        assert needs('E02-S4', T) == [], needs('E02-S4', T)  # E03-S1 <-> E03-S2 parent loop: no open leaf, and no hang
        assert leaves('E04', T) == [] and leaves('E09', T) == [] and leaves('E02', T) == ['E02-S1', 'E02-S4']  # done epic; not on this board
        F = tree({'b/items/EPIC-05-x/epic.md': C('E05', dependsOn='E02-S1'), 'b/items/EPIC-05-x/stories/S1.md': C('E05-S1'),
                  'b/items/EPIC-02-y/stories/S1.md': C('E02-S1')})  # a story with no `parent:` belongs to its folder's epic
        assert needs('E05-S1', F) == [('E02-S1', 'E05', 'E02-S1')] and leaves('E05', F) == ['E05-S1'], needs('E05-S1', F)
        print('regen-board self-test: OK'); return
    proj = None
    if '--project' in args:
        i = args.index('--project')
        if i + 1 >= len(args): sys.exit('regen-board: --project needs a name')
        proj = args[i + 1]; del args[i:i + 2]
    B = os.path.abspath(os.path.expanduser(args[0] if args else os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'):
        sys.exit(f'regen-board: no items/ folder in {B}')
    if not proj:
        parent = os.path.dirname(B)  # <repo>/.claude/backlog -> name the repo, not ".claude"
        if os.path.basename(parent) == '.claude': parent = os.path.dirname(parent)
        proj = open(f'{B}/.project').read().strip() if os.path.exists(f'{B}/.project') else os.path.basename(parent)

    open(f'{B}/BOARD.md', 'w').write(render(B, proj))

if __name__ == '__main__':
    main(sys.argv[1:])
