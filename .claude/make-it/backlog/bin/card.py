#!/usr/bin/env python3
"""Write a board card safely -- the one way card writes happen.

Usage: card.py [--board PATH] [--project NAME] [--no-sync] append <id> <section>   (text on stdin)
       card.py [--board PATH] [--project NAME] [--no-sync] set <id> key=value ...   (key= removes it)
       card.py [--board PATH] [--project NAME] [--no-sync] new <epic-id>            (a whole card on stdin, `id: NEW`)
       card.py --self-test
  --board defaults to $BACKLOG_DIR, then ./.claude/backlog.
Every write pulls first (a board in its own repo), finds the card by its `id:` (exactly one), writes
the whole file and then swaps it in, bumps `updated:`, regenerates BOARD.md, and syncs: commit + push
for a board in its own repo, stage only for a board inside a project, nothing with --no-sync.
Text comes from stdin, so no shell quoting, `%` or glob ever touches it.
"""
import datetime, importlib.util, os, re, subprocess, sys

_bin = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(_bin, 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
v = R.v

def write(p, fields=None, section=None, text=None, T=None):
    """Set (value) or remove (None) frontmatter fields, append `text` under `## section`, bump updated:."""
    T = T or datetime.date.today()
    txt = open(p).read()
    m = re.match(r'---\n(.*?)\n---', txt, re.S)
    if not m: sys.exit(f'card: no frontmatter in {p}')
    lines = m.group(1).split('\n')
    for k, val in dict(fields or {}, updated=str(T)).items():
        i = next((i for i, l in enumerate(lines) if re.match(rf'{re.escape(k)}\s*:', l)), None)
        if val is None: lines = [l for j, l in enumerate(lines) if j != i]
        elif i is None: lines.append(f'{k}: {val}')
        else: lines[i] = f'{k}: {val}'
    body = txt[m.end():].rstrip('\n')
    if section is not None:
        text = text.strip('\n')
        h = re.search(rf'^## {re.escape(section)}(?!\w).*$', body, re.M)  # an existing section grows; else a new one
        if h:
            end = re.search(r'^## ', body[h.end():], re.M)
            cut = h.end() + (end.start() if end else len(body) - h.end())
            body = body[:cut].rstrip('\n') + '\n' + text + ('\n\n' + body[cut:].lstrip('\n') if end else '')
        else: body += f'\n\n## {section}\n{text}'
    tmp = f'{p}.{os.getpid()}.tmp'
    with open(tmp, 'w') as f:  # whole file, then swap: a crash never leaves half a card
        f.write('---\n' + '\n'.join(lines) + '\n---' + body + '\n')
    os.replace(tmp, p)

def regen(B, proj): subprocess.run([sys.executable, os.path.join(_bin, 'regen-board.py'), B] + (['--project', proj] if proj else []), check=True)

_locks = {}
def lock(B):  # one card writer per board at a time, taken after stdin is read (held until exit; once per process)
    import fcntl
    if B not in _locks: _locks[B] = os.open(f'{B}/items', os.O_RDONLY); fcntl.flock(_locks[B], fcntl.LOCK_EX)

def git(B, *a): return subprocess.run(['git', '-C', B, *a], capture_output=True, text=True)

def own_repo(B):  # a board that is its own git repo commits and pushes; one inside a project only stages
    top = git(B, 'rev-parse', '--show-toplevel')
    return None if top.returncode else os.path.samefile(top.stdout.strip(), B)

def pull(B):
    if own_repo(B) and git(B, 'symbolic-ref', '-q', 'HEAD').returncode: sys.exit('card: board repo is not on a branch (detached or mid-rebase) -- fix it first, nothing written')
    if own_repo(B) and not git(B, 'rev-parse', '--abbrev-ref', '@{u}').returncode:
        r = git(B, 'pull', '-q', '--ff-only')
        if r.returncode: sys.exit(f'card: pull failed, nothing written -- {r.stderr.strip()[:200]}')

def sync(B, paths, msg, proj):
    regen(B, proj)
    own = own_repo(B)
    if own is None: return 'not in git'
    paths = [os.path.relpath(p, B) for p in paths] + ['BOARD.md']
    git(B, 'add', '--', *paths)
    if not own: return 'staged (board inside a project)'
    c = git(B, 'commit', '-q', '-m', msg, '--', *paths)
    if c.returncode: return 'nothing to commit' if not git(B, 'status', '--porcelain', '--', *paths).stdout.strip() else sys.exit(f'card: written, commit failed -- {c.stderr.strip()[:200]}')
    if git(B, 'rev-parse', '--abbrev-ref', '@{u}').returncode: return 'committed (no remote)'
    if git(B, 'push', '-q').returncode:  # someone pushed meanwhile: replay ours on top, once
        if (r := git(B, 'pull', '-q', '--rebase')).returncode:
            if git(B, 'diff', '--name-only', '--diff-filter=U').stdout.split() == ['BOARD.md']:
                regen(B, proj); git(B, 'add', 'BOARD.md')
                ok = not subprocess.run(['git', '-C', B, '-c', 'core.editor=true', 'rebase', '--continue'], capture_output=True).returncode
            else: ok = False
            if not ok:
                git(B, 'rebase', '--abort')  # never leave a board mid-rebase; the commit stays on the branch, unpushed
                sys.exit(f'card: committed, not pushed -- the rebase onto the newer board failed ({(r.stderr.strip() or "conflict")[:160]}); pull --rebase and push by hand')
        if git(B, 'push', '-q').returncode: sys.exit('card: committed, push failed -- pull --rebase and push by hand')
    return 'committed + pushed'

def find(B, cid):
    hits = [p for p, d in R.load(B).items() if v(d, 'id').upper() == cid.upper()]
    if len(hits) != 1: sys.exit(f'card: {cid} matches {len(hits)} cards' + (f': {", ".join(hits)}' if hits else ''))
    return hits[0]

def new(B, epic, text, T=None):
    """File a new card under `epic` from text whose frontmatter has `id: NEW`. Returns (id, path)."""
    T = T or datetime.date.today()
    eps = [p for p, d in R.load(B).items() if p.endswith('/epic.md') and v(d, 'id').upper() == epic.upper()]
    if len(eps) != 1: sys.exit(f'card: epic {epic} matches {len(eps)} epics')
    epic = v(R.fm(eps[0]), 'id')
    f = re.match(r'---\n(.*?)\n---', text.lstrip('\n'), re.S)
    if not f or not re.search(r'^id:\s*NEW\s*$', f.group(1), re.M): sys.exit('card: the new card needs `id: NEW` in its frontmatter')
    n = 1 + max([int(m.group(1)) for d in R.load(B).values() if (m := re.match(rf'{re.escape(epic)}-S(\d+)$', v(d, 'id'), re.I))] or [0])
    cid = f'{epic}-S{n}'
    title = (re.search(r'^title:\s*(.+)$', text, re.M) or [None, 'card'])[1].strip('"')
    slug = '-'.join(re.findall(r'[a-z0-9]+', title.lower())[:6]) or 'card'
    d = os.path.join(os.path.dirname(eps[0]), 'stories'); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, f'S{n}-{slug}.md')
    if os.path.exists(p): sys.exit(f'card: {p} already exists')
    with open(p, 'x') as f: f.write(re.sub(r'^id:\s*NEW\s*$', f'id: {cid}', text.strip('\n') + '\n', count=1, flags=re.M))
    have = R.fm(p)
    write(p, {k: x for k, x in (('parent', epic), ('created', str(T))) if not v(have, k)}, T=T)
    return cid, p

def main(args):
    opts = {}
    for k in ('--board', '--project'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'card: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    nosync = '--no-sync' in args; args = [a for a in args if a != '--no-sync']
    B = os.path.abspath(os.path.expanduser(opts.get('--board') or os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'card: no items/ folder in {B}')
    verb, rest = (args[0], args[1:]) if args else ('', [])
    def stdin():  # the text to write: never a terminal (it would wait forever), never empty (a lost heredoc)
        if sys.stdin.isatty(): sys.exit('card: pipe the text on stdin')
        t = sys.stdin.read()
        return t if t.strip() else sys.exit('card: empty text on stdin, nothing written')
    if verb == 'append' and len(rest) == 2:
        t = stdin(); lock(B); pull(B); p = find(B, rest[0]); write(p, section=rest[1], text=t); what = f'{v(R.fm(p), "id")}: {rest[1]}'
    elif verb == 'set' and len(rest) >= 2 and all('=' in a for a in rest[1:]):
        fields = dict(a.split('=', 1) for a in rest[1:])
        if 'id' in fields: sys.exit('card: id is not settable')
        if any(not re.fullmatch(r'[A-Za-z_][\w-]*', k) or re.search(r'[\r\n]', x) for k, x in fields.items()): sys.exit('card: bad key or a newline in a value')
        lock(B); pull(B); p = find(B, rest[0])
        if 'decision' in fields and v(R.fm(p), 'answers'): fields.setdefault('answers', '')  # answers belong to their question: a new or cleared one drops the old
        write(p, {k: (x or None) for k, x in fields.items()})
        what = f'{v(R.fm(p), "id")}: ' + ', '.join(f'{k}={x}' if x else f'-{k}' for k, x in fields.items())
    elif verb == 'new' and len(rest) == 1:
        t = stdin(); lock(B); pull(B); cid, p = new(B, rest[0], t); what = f'new {cid}: {v(R.fm(p), "title")}'
    else: sys.exit(__doc__)
    print(f'{what} · {"not synced (--no-sync)" if nosync else sync(B, [p], f"card: {what}"[:72], opts.get("--project"))}')

def self_test():
    import tempfile
    T = str(datetime.date.today())
    run = lambda *a, stdin='', ok=True: (lambda r: (r, (r.returncode == 0) == ok or sys.exit(f'{a}: rc={r.returncode} {r.stdout}{r.stderr}')))(
        subprocess.run([sys.executable, __file__, *a], input=stdin, capture_output=True, text=True))[0]
    g = lambda d, *a: subprocess.run(['git', '-C', d, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false',
                                      '-c', 'core.hooksPath=/dev/null', *a], capture_output=True, text=True, check=True).stdout
    with tempfile.TemporaryDirectory() as t:
        os.environ.update(GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t')
        subprocess.run(['git', 'init', '-q', '--bare', f'{t}/remote.git'], check=True)
        A = f'{t}/a'; subprocess.run(['git', 'clone', '-q', f'{t}/remote.git', A], check=True, capture_output=True)
        os.makedirs(f'{A}/items/EPIC-01-x/stories')
        open(f'{A}/items/EPIC-01-x/epic.md', 'w').write('---\nid: E01\ntitle: X\nstatus: in-progress\n---\n')
        open(f'{A}/items/EPIC-01-x/stories/S1-one.md', 'w').write('---\nid: E01-S1\ntitle: One\nstatus: in-progress\npriority: P2\nstage: Fix ready\ndecision: Ship it?\nanswers: Go -- ship | Wait -- hold\n---\n\n## Answers\n- old\n\n## Notes\nkeep\n')
        g(A, 'add', '-A'); g(A, 'commit', '-qm', 'seed'); g(A, 'push', '-q', 'origin', 'HEAD')
        S1 = f'{A}/items/EPIC-01-x/stories/S1-one.md'
        tricky = '- 50% done, *.md kept, $HOME and `x` -- é ✓\n'  # what printf, globs and shells mangle
        out = run('--board', A, 'append', 'e01-s1', 'Answers', stdin=tricky).stdout
        c = open(S1).read()
        assert tricky.strip() in c and c.index('- old') < c.index('50% done') < c.index('## Notes'), c  # grows its section
        assert f'updated: {T}' in c and 'committed + pushed' in out and 'E01-S1 · ' in open(f'{A}/BOARD.md').read(), out
        assert 'card: E01-S1: Answers' in g(f'{t}/remote.git', 'log', '-1', '--format=%s'), 'not pushed'
        run('--board', A, 'append', 'E01-S1', 'Done (today)', stdin='- shipped\n')
        run('--board', A, 'append', 'E01-S1', 'Done (today)', stdin='- again\n')  # a heading ending in ')' still grows
        assert open(S1).read().count('## Done (today)') == 1 and open(S1).read().rstrip().endswith('- shipped\n- again'), open(S1).read()
        run('--board', A, 'set', 'E01-S1', 'status=done', 'decision=', 'stage=Checked', 'pr=[12]')
        d = R.fm(S1)
        assert (v(d, 'status'), v(d, 'stage'), v(d, 'pr'), 'decision' in d, 'answers' in d, v(d, 'priority')) == ('done', 'Checked', '[12]', False, False, 'P2'), d
        run('--board', A, 'set', 'E01-S1', 'decision=Old question?', 'answers=Go -- a | Wait -- b')
        assert v(R.fm(S1), 'answers') == 'Go -- a | Wait -- b', R.fm(S1)  # the same write's answers stay
        run('--board', A, 'set', 'E01-S1', 'stage=Fix ready', 'pr=[13]', 'signal=x')  # a lane's PR write, not touching decision
        assert v(R.fm(S1), 'answers') == 'Go -- a | Wait -- b', R.fm(S1)
        run('--board', A, 'set', 'E01-S1', 'decision=New question?')  # a new question never inherits the old answers
        assert (v(R.fm(S1), 'decision'), 'answers' in R.fm(S1)) == ('New question?', False), R.fm(S1)
        run('--board', A, 'set', 'E01-S1', 'answers=Go -- a | Wait -- b'); run('--board', A, 'set', 'E01-S1', 'decision=')
        assert not {'decision', 'answers'} & set(R.fm(S1)), R.fm(S1)
        assert '-answers' not in run('--board', A, 'set', 'E01-S1', 'decision=').stdout  # the card had none: none logged
        before = open(S1).read()
        assert 'matches 0 cards' in run('--board', A, 'set', 'E01-S9', 'status=done', ok=False).stderr
        assert 'not settable' in run('--board', A, 'set', 'E01-S1', 'id=E01-S7', ok=False).stderr and open(S1).read() == before
        B2 = f'{t}/b'; subprocess.run(['git', 'clone', '-q', f'{t}/remote.git', B2], check=True, capture_output=True)  # a stale clone
        card = '---\nid: NEW\ntitle: "Fix the 100% * case"\ntype: breakfix\nstatus: backlog\n---\n\n## Goal\nx\n'
        out = run('--board', A, 'new', 'e01', stdin=card).stdout
        assert 'new E01-S2' in out and os.path.exists(f'{A}/items/EPIC-01-x/stories/S2-fix-the-100-case.md'), out
        n = R.fm(f'{A}/items/EPIC-01-x/stories/S2-fix-the-100-case.md')
        assert (v(n, 'id'), v(n, 'parent'), v(n, 'created')) == ('E01-S2', 'E01', T), n
        out = run('--board', B2, 'new', 'E01', stdin=card.replace('100% * case', 'other')).stdout  # pulls first: no clash
        assert 'new E01-S3' in out, out
        assert 'needs `id: NEW`' in run('--board', A, 'new', 'E01', stdin='---\ntitle: x\n---\n', ok=False).stderr
        open(f'{A}/items/EPIC-01-x/stories/S9-dup.md', 'w').write('---\nid: E01-S1\n---\n')
        assert 'matches 2 cards' in run('--board', A, 'set', 'E01-S1', 'status=done', ok=False).stderr
        os.remove(f'{A}/items/EPIC-01-x/stories/S9-dup.md')
        head = g(A, 'rev-parse', 'HEAD')
        assert 'not synced' in run('--board', A, '--no-sync', 'set', 'E01-S1', 'size=S').stdout and g(A, 'rev-parse', 'HEAD') == head
        P = f'{t}/proj'; os.makedirs(f'{P}/.claude'); subprocess.run(['git', 'init', '-q', P], check=True)  # a board inside a project
        subprocess.run(['cp', '-R', f'{A}/items', f'{P}/.claude/backlog-items'], check=True); os.makedirs(f'{P}/.claude/backlog')
        os.rename(f'{P}/.claude/backlog-items', f'{P}/.claude/backlog/items')
        out = run('--board', f'{P}/.claude/backlog', 'set', 'E01-S2', 'status=in-progress').stdout
        assert 'staged (board inside a project)' in out, out  # staged, never committed
        assert '.claude/backlog/items/EPIC-01-x/stories/S2-fix-the-100-case.md' in g(P, 'diff', '--cached', '--name-only'), 'not staged'
        # --- review fixes ---
        st = lambda f: open(f).read()
        run('--board', A, 'set', 'E01-S1', 'size=S')  # commit the --no-sync write above: the board is clean again
        S3 = [f'{A}/items/EPIC-01-x/stories/{f}' for f in os.listdir(f'{A}/items/EPIC-01-x/stories') if f.startswith('S3-')][0]
        C3 = f'{t}/c'; subprocess.run(['git', 'clone', '-q', f'{t}/remote.git', C3], check=True, capture_output=True)
        run('--board', C3, 'set', 'E01-S2', 'status=done')  # another session closes S2 and pushes
        write(S3, {'status': 'done'}); res = sync(A, [S3], 'race', None)  # ours, unpulled: push rejected, BOARD.md conflicts
        b = st(f'{A}/BOARD.md')
        assert res == 'committed + pushed' and '<<<<' not in b and not subprocess.run(['git', '-C', A, 'symbolic-ref', '-q', 'HEAD'], capture_output=True).returncode, res
        assert b.split('### done')[1].count('E01-S2 ·') == 1 and 'E01-S3 ·' in b.split('### done')[1], b  # both closes kept
        g(A, 'checkout', '-q', '--detach'); before = st(S1)
        assert 'not on a branch' in run('--board', A, 'set', 'E01-S1', 'size=M', ok=False).stderr and st(S1) == before
        g(A, 'checkout', '-q', '-')
        open(f'{A}/.git/index.lock', 'w').close()  # another git process holds the index: say so, exit non-zero
        assert 'commit failed' in run('--board', A, 'set', 'E01-S1', 'size=L', ok=False).stderr
        os.remove(f'{A}/.git/index.lock'); run('--board', A, 'set', 'E01-S1', 'size=L')
        if os.path.isdir(f'{t}/A'):  # case-insensitive disk: --board in another case is still the same repo
            assert 'committed + pushed' in run('--board', f'{t}/A', 'set', 'E01-S1', 'size=XL').stdout
        before = st(S1)
        assert 'empty text' in run('--board', A, 'append', 'E01-S1', 'Answers', stdin=' \n', ok=False).stderr
        assert 'bad key or a newline' in run('--board', A, 'set', 'E01-S1', 'decision=a\n---\nstatus: done', ok=False).stderr
        assert 'bad key' in run('--board', A, 'set', 'E01-S1', '=x', ok=False).stderr and st(S1) == before
        n0 = len(os.listdir(f'{A}/items/EPIC-01-x/stories'))
        assert 'needs `id: NEW`' in run('--board', A, 'new', 'E01', stdin='id: NEW\ntitle: no fences\n', ok=False).stderr
        assert 'needs `id: NEW`' in run('--board', A, 'new', 'E01', stdin='---\nid: E01-S1\n---\nid: NEW\n', ok=False).stderr
        assert len(os.listdir(f'{A}/items/EPIC-01-x/stories')) == n0, 'a refused new card left a file'
        PB = f'{P}/.claude/backlog'  # many writers at once (no upstream: the worst case for ids): nothing lost, no id twice
        ps = [subprocess.Popen([sys.executable, __file__, '--board', PB, '--no-sync', 'append', 'E01-S1', 'Burst'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(8)]
        ps += [subprocess.Popen([sys.executable, __file__, '--board', PB, '--no-sync', 'new', 'E01'], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(4)]
        outs = [q.communicate(f'- line {i}\n' if i < 8 else card)[0] for i, q in enumerate(ps)]
        assert all(f'- line {i}' in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md') for i in range(8)), outs
        ids = [re.search(r'new (E01-S\d+)', o).group(1) for o in outs[8:]]
        assert len(set(ids)) == 4, ids
        import fcntl, time  # the lock is really taken: a writer waits while another holds it
        fd = os.open(f'{PB}/items', os.O_RDONLY); fcntl.flock(fd, fcntl.LOCK_EX)
        q = subprocess.Popen([sys.executable, __file__, '--board', PB, '--no-sync', 'append', 'E01-S1', 'Burst'], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        q.stdin.write('- waited\n'); q.stdin.close(); time.sleep(1.5)
        assert q.poll() is None and '- waited' not in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md'), 'wrote without the lock'
        fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd); q.wait(30)
        assert '- waited' in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md'), q.stderr.read()
        assert not [f for d in (A, PB) for f in os.listdir(f'{d}/items/EPIC-01-x/stories') if f.endswith('.tmp')]
    print('card self-test: OK')

if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']: self_test(); sys.exit(0)
    main(sys.argv[1:])
