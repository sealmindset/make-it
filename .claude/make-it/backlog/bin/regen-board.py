#!/usr/bin/env python3
"""Render <board>/BOARD.md from card frontmatter (items/ only; archive/ is not shown).

Usage: regen-board.py [board_dir] [--project NAME]
       regen-board.py --self-test
  board_dir  defaults to $BACKLOG_DIR, then ./.claude/backlog
  --project  defaults to <board>/.project, then the project folder's name
"""
import datetime, glob, os, re, sys

ORDER = ['in-progress', 'ready', 'blocked', 'designing', 'backlog', 'done']
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
def age(d):
    try: return f" · {(datetime.date.today() - datetime.date.fromisoformat(v(d, 'updated'))).days}d"
    except ValueError: return ''
def blocked(s, status):  # can't start: high-stakes, waiting on you, or waiting on an unfinished card
    deps = [x.strip().upper() for x in v(s, 'dependsOn').strip('[]').split(',') if x.strip()]
    # ponytail: an id not on this board doesn't block -- it may live on another board
    return bool(warn(s)) or waiting(s) or not all(status.get(d, 'done') == 'done' for d in deps)
def bucket(s):  # which bug-queue status line an open card sits on, if any
    if v(s, 'status') == 'done': return None
    if v(s, 'stage') in ('Reported', 'Cause found'): return 'Now fixing' if v(s, 'status') == 'in-progress' and not waiting(s) else None
    return {'Fix ready': 'Shipping', 'Live': 'Live, to check'}.get(v(s, 'stage'))
def startable(s, status): return v(s, 'status') == 'backlog' and not blocked(s, status)  # Next up
def next_up(stories, status):
    return next((v(s, 'id').split('-')[-1] for s in sorted(stories, key=lambda s: (v(s, 'priority') or 'P9', num(s)))
                 if v(s, 'type') == 'breakfix' and startable(s, status)), '—')

def render(B, proj):
    CARDS = list(load(B).values())
    STATUS = {v(d, 'id').upper(): v(d, 'status') for d in CARDS}
    out = [f'# BACKLOG BOARD — {proj}', '']
    wait = sorted(filter(waiting, CARDS), key=lambda d: (v(d, 'priority') or 'P9', v(d, 'updated') or '9'))
    if wait:
        out += [f'## Waiting on you ({len(wait)})', '_the question each card waits on · days since the card last changed_', '']
        out += [f"- {warn(d)}{v(d,'id')} · {v(d,'decision') or '(question not on card -- add `decision:`)'}{age(d)}" for d in wait] + ['']
    for ep in sorted(glob.glob(f'{B}/items/*/epic.md')):
        e = fm(ep)
        stories = [fm(s) for s in glob.glob(os.path.join(os.path.dirname(ep), 'stories', '*.md'))]
        stories.sort(key=lambda s: (ORDER.index(v(s, 'status')) if v(s, 'status') in ORDER else 9, num(s)))
        counts = ' · '.join(f'{st} {n}' for st in ORDER if (n := sum(v(s, 'status') == st for s in stories)))
        out += [f"## {warn(e)}{v(e,'id')} · {v(e,'title')}  _[{v(e,'status')}]_{chips(e)}", f'_{counts}_', '']
        if any(v(s, 'type') == 'breakfix' for s in stories):
            # The bug queue status line: Reported -> Cause found -> Fix ready -> Live -> Checked.
            def ids(pred): return ', '.join(v(s, 'id').split('-')[-1] for s in stories if pred(s)) or '—'
            nxt = next_up(stories, STATUS)
            out += [f'**{k}:** ' + ids(lambda s: bucket(s) == k) for k in ('Now fixing', 'Shipping', 'Live, to check')] + [
                    '**Next up:** ' + nxt, '']
        for st in ORDER:
            group = [s for s in stories if v(s, 'status') == st]
            if not group: continue
            out.append(f'### {st} ({len(group)})')
            for s in group:
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
            card('stories/S3.md', id='E01-S3', status='backlog', type='breakfix', priority='P2', decision='Retry, or refile?')
            card('stories/S4.md', id='E01-S4', status='in-progress', type='breakfix', stage='Cause found', decision='Narrow fix or wide?')
            card('stories/S6.md', id='E01-S6', status='in-progress', type='breakfix', stage='Needs decision')
            card('stories/S7.md', id='E01-S7', status='backlog', type='story', decision='Which tier?')
            card('stories/S8.md', id='E01-S8', status='done', type='story', decision='Old question')
            b = board()
            assert '## Waiting on you (4)' in b and '- E01-S3 · Retry, or refile?' in b and '- E01-S7 · Which tier?' in b, b
            assert '- E01-S6 · (question not on card' in b and 'Old question' not in b, b
            assert '**Now fixing:** —' in b and '**Next up:** —' in b, b
            card('stories/S3.md', id='E01-S3', status='backlog', type='breakfix', priority='P2')  # answered
            b = board()
            assert '**Next up:** S3' in b and 'Retry, or refile?' not in b and '## Waiting on you (3)' in b, b
            card('stories/S9.md', id='E01-S9', status='backlog', type='story', priority='P1')  # Next up is a bug
            assert '**Next up:** S3' in board()
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
