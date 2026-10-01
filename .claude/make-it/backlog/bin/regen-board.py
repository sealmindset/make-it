#!/usr/bin/env python3
"""Render <board>/BOARD.md from card frontmatter (items/ only; archive/ is not shown).

Usage: regen-board.py [board_dir] [--project NAME]
  board_dir  defaults to $BACKLOG_DIR, then ./.claude/backlog
  --project  defaults to <board>/.project, then the project folder's name
"""
import glob, os, re, sys

args = sys.argv[1:]
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

ORDER = ['in-progress', 'ready', 'blocked', 'designing', 'backlog', 'done']
def fm(p):
    m = re.match(r'---\n(.*?)\n---', open(p).read(), re.S)
    return dict(l.split(':', 1) for l in m.group(1).splitlines() if ':' in l) if m else {}
def v(d, k): return d.get(k, '').strip()
def num(s): return int(re.sub(r'\D', '', v(s, 'id').split('-S')[-1]) or 0)
def chips(d): return (f" [{v(d,'size')}]" if v(d, 'size') else '') + (f" 📌{v(d,'pin')}" if v(d, 'pin') else '')
def warn(d): return '⚠️' if v(d, 'stakes') == 'critical' else ''

out = [f'# BACKLOG BOARD — {proj}', '']
for ep in sorted(glob.glob(f'{B}/items/*/epic.md')):
    e = fm(ep)
    stories = [fm(s) for s in glob.glob(os.path.join(os.path.dirname(ep), 'stories', '*.md'))]
    stories.sort(key=lambda s: (ORDER.index(v(s, 'status')) if v(s, 'status') in ORDER else 9, num(s)))
    counts = ' · '.join(f'{st} {n}' for st in ORDER if (n := sum(v(s, 'status') == st for s in stories)))
    out += [f"## {warn(e)}{v(e,'id')} · {v(e,'title')}  _[{v(e,'status')}]_{chips(e)}", f'_{counts}_', '']
    if any(v(s, 'type') == 'breakfix' for s in stories):
        # The bug queue status line: Reported -> Cause found -> Fix ready -> Live -> Checked.
        def ids(pred): return ', '.join(v(s, 'id').split('-')[-1] for s in stories if pred(s)) or '—'
        op = lambda s: v(s, 'status') != 'done'
        nxt = next((v(s, 'id').split('-')[-1] for s in sorted(stories, key=lambda s: (v(s, 'priority') or 'P9', num(s))) if v(s, 'status') == 'backlog'), '—')
        out += ['**Now fixing:** ' + ids(lambda s: op(s) and v(s, 'status') == 'in-progress' and v(s, 'stage') in ('Reported', 'Cause found')),
                '**Shipping:** ' + ids(lambda s: op(s) and v(s, 'stage') == 'Fix ready'),
                '**Live, to check:** ' + ids(lambda s: op(s) and v(s, 'stage') == 'Live'),
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
open(f'{B}/BOARD.md', 'w').write('\n'.join(out))
