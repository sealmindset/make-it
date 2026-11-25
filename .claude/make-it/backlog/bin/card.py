#!/usr/bin/env python3
"""Write a board card safely -- the one way card writes happen.

Usage: card.py [--board PATH] [--project NAME] [--no-sync] append <id> <section>   (text on stdin)
       card.py [--board PATH] [--project NAME] [--no-sync] set <id> key=value ...   (key= removes it)
       card.py [--board PATH] [--project NAME] [--no-sync] new <epic-id>            (a whole card on stdin, `id: NEW`)
       card.py [--board PATH] [--project NAME] [--no-sync] capture [triage-file]    (the report on stdin, word for word)
       card.py --self-test
  --board defaults to $BACKLOG_DIR, then ./.claude/backlog.
Every write pulls first (a board in its own repo), finds the card by its `id:` (exactly one), writes
the whole file and then swaps it in, bumps `updated:`, regenerates BOARD.md, and syncs: commit + push
for a board in its own repo, stage only for a board inside a project, nothing with --no-sync.
Text comes from stdin, so no shell quoting, `%` or glob ever touches it.
A bundle (see shrink.py) keeps each card's own point: `set <id> status=done` is refused for a part of an open bundle
(it closes on its own check, with `shrink.py part-done`) and for a bundle whose parts are still open.
`capture` is how a report is never lost: it checks what the triage call gave back (the file; none = the call
gave nothing). Bad output -> the report becomes a card under the Bugs epic, a bug at Reported, marked "not
sorted yet -- triage failed: <reason>". Good output -> `triage ok`, nothing written: write the sorted card with `new`.
The line printed ends with what happened, and it is true: `committed + pushed` only when the shared board has
it; otherwise `... NOT sent to ...: <reason>`. Exit 0 = sent, or the board has no shared copy to send to (no
remote, inside a project, not in git, --no-sync). Exit 3 = written here, but the shared board did not get it.
Any other non-zero exit = nothing written. Exit 3 means saved here but not sent: do not repeat the write.
"""
import datetime, importlib.util, json, os, re, subprocess, sys

_bin = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(_bin, 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
v = R.v

def write(p, fields=None, section=None, text=None, T=None):
    """Set (value) or remove (None) frontmatter fields, append `text` under `## section`, bump updated:."""
    T = T or datetime.date.today()
    try: raw = open(p, encoding='utf-8-sig', newline='').read()  # a leading BOM is dropped, and never written back
    except UnicodeDecodeError: sys.exit(f'card: {p} is not UTF-8 text, nothing written -- re-save it as UTF-8')
    nl = '\r\n' if '\r\n' in raw else '\n'  # the card keeps its own line endings
    txt = raw.replace('\r\n', '\n')
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
    try:
        with open(tmp, 'w', encoding='utf-8', newline=nl) as f:  # whole file, then swap: a crash never leaves half a card
            f.write('---\n' + '\n'.join(lines) + '\n---' + body + '\n')
        os.replace(tmp, p)
    except BaseException as e:
        if os.path.exists(tmp): os.remove(tmp)  # no temp file left behind, whatever failed
        if isinstance(e, UnicodeEncodeError): sys.exit(f'card: the text for {p} is not UTF-8, nothing written')
        raise

def regen(B, proj): subprocess.run([sys.executable, os.path.join(_bin, 'regen-board.py'), B] + (['--project', proj] if proj else []), check=True)

_locks = {}
def lock(B):  # one card writer per board at a time, taken after stdin is read (held until exit; once per process)
    import fcntl
    if B not in _locks: _locks[B] = os.open(f'{B}/items', os.O_RDONLY); fcntl.flock(_locks[B], fcntl.LOCK_EX)

def git(B, *a, input=None): return subprocess.run(['git', '-C', B, *a], capture_output=True, text=True, encoding='utf-8', errors='replace', input=input)

def own_repo(B):  # a board that is its own git repo commits and pushes; one inside a project only stages
    top = git(B, 'rev-parse', '--show-toplevel')
    return None if top.returncode else os.path.samefile(top.stdout.strip(), B)

NS = 'NOT sent to the shared board'
class NotSent(Exception): pass  # written here, but the shared board did not get it: exit 3

_moved = {}  # a card renumber() moved: old path -> new path
def renumber(B, proj):
    """Two clones gave two new cards one id: ours, not on the shared board yet, takes the next free id (its own
    commit). Never silently: a line on stdout with both titles and ids, and a line on the card saying what it was.
    Our other new cards not sent yet that depend on it follow (`dependsOn:`); a card on the shared board is never
    edited for this -- any card of ours that still mentions the old id is named on the line instead."""
    said = []
    unsent = lambda *f: {os.path.join(B, r) for r in git(B, 'diff', '--name-only', *f, '@{u}..HEAD', '--', 'items').stdout.split('\n') if r}
    for rel in git(B, 'diff', '--name-only', '--diff-filter=A', '@{u}..HEAD', '--', 'items').stdout.split('\n'):
        p, cards = os.path.join(B, rel), R.load(B)
        cid = v(cards.get(p) or {}, 'id'); epic = cid.rsplit('-S', 1)[0]
        if not rel or '-S' not in cid or sum(v(d, 'id').upper() == cid.upper() for d in cards.values()) < 2: continue
        n = 1 + max(int(m.group(1)) for d in cards.values() if (m := re.match(rf'{re.escape(epic)}-S(\d+)$', v(d, 'id'), re.I)))
        q = os.path.join(os.path.dirname(p), re.sub(r'^S\d+', f'S{n}', os.path.basename(p)))
        if q != p and (os.path.exists(q) or git(B, 'mv', p, q).returncode): continue
        title = lambda d: v(d, 'title').strip('"') or 'Untitled card'
        theirs = next(title(d) for x, d in cards.items() if x != p and v(d, 'id').upper() == cid.upper())
        txt = open(q, encoding='utf-8', newline='').read()
        with open(q, 'w', encoding='utf-8', newline='') as f: f.write(re.sub(r'^id:.*$', f'id: {epic}-S{n}', txt, count=1, flags=re.M))
        write(q, section='Renumbered', text=f'- this card was {cid} until {datetime.date.today()}: "{theirs}" took that id on the shared board first')
        word = re.compile(rf'(?<![\w-]){re.escape(cid)}(?!\d)', re.I)
        for x in sorted(unsent('--diff-filter=A') - {p, q}):  # new cards of ours the shared board has never seen
            if os.path.exists(x) and cid.upper() in R.ids(v(R.fm(x) or {}, 'dependsOn')):
                write(x, {'dependsOn': word.sub(f'{epic}-S{n}', v(R.fm(x), 'dependsOn'))}); git(B, 'add', '--', x)
        still = [R.name(R.fm(x)) for x in sorted(unsent() - {p, q}) if x in cards and os.path.exists(x) and word.search(open(x, encoding='utf-8').read())]
        print(f'Your card "{title(cards[p])}" is now {epic}-S{n}: {cid} was taken by "{theirs}" on the shared board'
              + (f' -- these cards still mention {cid}: {", ".join(still)}: check them' if still else ''), flush=True)
        git(B, 'add', '--', q); _moved[p] = q; _moved.update({k: q for k, x in _moved.items() if x == p}); said.append(f'{cid} is now {epic}-S{n}')
    if said: regen(B, proj); git(B, 'add', 'BOARD.md'); git(B, 'commit', '-q', '-F', '-', input=f'card: {", ".join(said)}: the shared board took that id meanwhile'[:120])

def catch_up(B, proj):
    """Put our commits the shared board lacks on top of its newer ones. None, or why not (never left mid-rebase).
    ponytail: settled here: a clash in BOARD.md (regenerated) and two new card files of one name (ours moves). Two clones
    changing the same lines of one card need a hand, and so does a later unsent change of ours to a card that had to move."""
    r = git(B, 'pull', '-q', '--rebase')
    for _ in range(50 if r.returncode else 0):  # one stop per commit of ours that clashes in a way settled here
        un = git(B, 'diff', '--name-only', '--diff-filter=U').stdout.split('\n')[:-1]
        both = [l[3:] for l in git(B, 'status', '--porcelain').stdout.split('\n') if l.startswith('AA items/') and re.match(r'S\d+', os.path.basename(l))]
        if not un or set(un) - {'BOARD.md'} - set(both): break
        for rel in both:  # both clones made a new card file of this name: theirs keeps it, ours moves to a free name (renumber() gives it its id)
            show = lambda stage: subprocess.run(['git', '-C', B, 'show', f':{stage}:{rel}'], capture_output=True, check=True).stdout
            m = re.match(r'S(\d+)(.*)', os.path.basename(rel)); n = int(m.group(1)) + 1
            while os.path.exists(q := os.path.join(B, os.path.dirname(rel), f'S{n}{m.group(2)}')): n += 1
            with open(q, 'wb') as f: f.write(show(3))  # stage 3 is our commit being replayed, stage 2 the shared board's
            with open(os.path.join(B, rel), 'wb') as f: f.write(show(2))
            git(B, 'add', '--', rel, q); _moved[os.path.join(B, rel)] = q
        if 'BOARD.md' in un: regen(B, proj); git(B, 'add', 'BOARD.md')
        if not subprocess.run(['git', '-C', B, '-c', 'core.editor=true', 'rebase', '--continue'], capture_output=True).returncode: r = None; break
    if r is not None and r.returncode:
        clash = git(B, 'diff', '--name-only', '--diff-filter=U').stdout.split()
        git(B, 'rebase', '--abort')
        if clash: return f'this board and the shared board both changed the same lines of {", ".join(clash)[:120]}'
        return ' '.join(' '.join(l for l in r.stderr.splitlines() if not l.startswith('hint:')).split())[:120] or 'git gave no reason'
    renumber(B, proj)

def pull(B, proj=None, soft=False):
    """Catch up with the shared board before a write. A failure writes nothing -- unless `soft` (a report is
    written anyway): then it returns why the board repo can't take a commit, or None."""
    if not own_repo(B): return None
    if git(B, 'symbolic-ref', '-q', 'HEAD').returncode:
        return 'the board repo is not on a branch (detached or mid-rebase)' if soft else sys.exit('card: board repo is not on a branch (detached or mid-rebase) -- fix it first, nothing written')
    if not git(B, 'rev-parse', '--abbrev-ref', '@{u}').returncode:
        r = git(B, 'pull', '-q', '--ff-only')
        if r.returncode and (why := catch_up(B, proj)) and not soft:
            sys.exit(f'card: nothing written -- could not catch up with the shared board: {why}. Run `git -C {B} pull --rebase`, settle what it names, then `git -C {B} push`')

def left_behind(B):
    """Card files saved here that git does not hold yet (an earlier write could not commit): untracked or staged
    as new, under items/, and loading as a card with an `id:` -- the same files the board shows. Nothing else is
    touched, and never a link (nor a file reached through one): what it points at is not the board's."""
    cards = R.load(B)
    names = git(B, 'ls-files', '--others', '--exclude-standard', '--', 'items').stdout.split('\n') + git(B, 'diff', '--cached', '--name-only', '--diff-filter=A', '--', 'items').stdout.split('\n')
    real = os.path.realpath(B)
    return [n for n in names if n and os.path.realpath(os.path.join(B, n)) == os.path.join(real, n) and v(cards.get(os.path.join(B, n)) or {}, 'id')]

def sync(B, paths, msg, proj):
    """Regenerate, commit, send. Returns what happened when that is all the board is set up for; raises NotSent
    when the board has a shared copy and the write did not get there."""
    regen(B, proj)
    own = own_repo(B)
    if own is None: return 'written here, NOT sent to a shared board: the board is not in git'
    paths = [os.path.relpath(p, B) for p in paths] + ['BOARD.md']
    git(B, 'add', '--', *paths)
    if not own: return "written here and staged, NOT sent to a shared board: the board lives inside a project and goes with that project's next commit"
    paths += [n for n in left_behind(B) if n not in paths]; git(B, 'add', '--', *paths)  # a card BOARD.md lists is a card the commit holds
    c = git(B, 'commit', '-q', '-F', '-', '--', *paths, input=msg)  # on stdin, as UTF-8: an ASCII locale can't put it in argv
    if c.returncode and git(B, 'status', '--porcelain', '--', *paths).stdout.strip():
        raise NotSent(f'written here, NOT committed and {NS}: the commit failed ({" ".join(c.stderr.split())[:120]})')
    here = 'nothing new to commit' if c.returncode else 'committed here'
    remotes = git(B, 'remote').stdout.split()
    if not remotes: return 'nothing to commit' if c.returncode else 'committed here, NOT sent to a shared board: the board has no remote (not shared yet)'
    if git(B, 'rev-parse', '--abbrev-ref', '@{u}').returncode:
        br = git(B, 'symbolic-ref', '--short', 'HEAD').stdout.strip()
        raise NotSent(f'{here}, {NS}: branch "{br}" follows no branch there -- run once: git -C {B} push -u {remotes[0]} {br}')
    if c.returncode and git(B, 'rev-list', '--count', '@{u}..HEAD').stdout.strip() == '0': return 'nothing to commit'
    if git(B, 'push', '-q').returncode:  # someone pushed meanwhile: replay ours on top, once
        if (why := catch_up(B, proj)): raise NotSent(f'{here}, {NS}: could not catch up with it ({why})')
        if (r := git(B, 'push', '-q')).returncode: raise NotSent(f'{here}, {NS}: the push failed ({" ".join(r.stderr.split())[:120]})')
    return 'nothing to commit, earlier commits pushed' if c.returncode else 'committed + pushed'

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
    title = (re.search(r'^title:\s*(.+)$', text, re.M) or [None, 'card'])[1].strip('"')
    slug = '-'.join(re.findall(r'[a-z0-9]+', title.lower())[:6]) or 'card'
    d = os.path.join(os.path.dirname(eps[0]), 'stories'); os.makedirs(d, exist_ok=True)
    while os.path.exists(p := os.path.join(d, f'S{n}-{slug}.md')): n += 1  # a stray file of that name never stops a new card
    cid = f'{epic}-S{n}'
    with open(p, 'x', encoding='utf-8') as f: f.write(re.sub(r'^id:\s*NEW\s*$', f'id: {cid}', text.strip('\n') + '\n', count=1, flags=re.M))
    have = R.fm(p)
    write(p, {k: x for k, x in (('parent', epic), ('created', str(T))) if not v(have, k)}, T=T)
    return cid, p

def triage_fault(B, raw):
    """Why what the triage call gave back can't sort a report -- or None when it can."""
    if raw is None or not raw.strip(): return 'no triage output'
    try: j = json.loads(re.sub(r'^\s*```\w*\n(.*?)\n```\s*$', r'\1', raw, flags=re.S))
    except ValueError: return f'not JSON ("{R.cut(" ".join(raw.split()), 60)}")'
    if not isinstance(j, dict): return 'the JSON is not an object'
    for k, good in (('type', 'epic story task breakfix spike'), ('size', 'XS S M L XL'), ('priority', 'P1 P2 P3')):
        if not isinstance(j.get(k), str) or j[k] not in good.split(): return f'missing or bad {k}'
    if not isinstance(j.get('title'), str) or not j['title'].strip(): return 'missing or bad title'
    pl = j.get('placement')
    if not isinstance(pl, dict) or pl.get('mode') not in ('existing', 'new'): return 'missing or bad placement'
    if pl['mode'] == 'new':
        ne = j.get('new_epic')
        return None if isinstance(ne, dict) and all(isinstance(ne.get(k), str) and ne[k].strip() for k in ('slug', 'title')) else 'missing or bad new_epic'
    epics = {v(d, 'id').upper() for p, d in R.load(B).items() if p.endswith('/epic.md')}
    return None if isinstance(pl.get('epic'), str) and pl['epic'].upper() in epics else f'epic {" ".join(str(pl.get("epic")).split())[:20]} is not on the board'

def bugs_epic(B, T=None):
    """(the Bugs epic's id, the path of its card when this call made it): made on first use."""
    T, cards = T or datetime.date.today(), R.load(B)
    eps = sorted(p for p, d in cards.items() if p.endswith('/epic.md') and v(d, 'title').strip('"').lower() == 'bugs')
    if eps: return v(cards[eps[0]], 'id'), None
    n = 1 + max([int(m.group(1)) for d in cards.values() if (m := re.fullmatch(r'E(\d+)', v(d, 'id'), re.I))] or [0])
    while os.path.exists(d := f'{B}/items/EPIC-{n:02d}-bugs'): n += 1
    os.makedirs(f'{d}/stories')
    with open(f'{d}/epic.md', 'x', encoding='utf-8') as f: f.write(f'---\nid: E{n:02d}\ntitle: Bugs\ntype: epic\nstatus: in-progress\ncreated: {T}\nupdated: {T}\n---\n')
    return f'E{n:02d}', f'{d}/epic.md'

def unsorted(report, why, T=None):
    """The card for a report triage could not sort: the person's words, line for line, under ## Captured."""
    lines = report.replace('\r\n', '\n').replace('\r', '\n').strip('\n').split('\n')
    first = next(l for l in lines if l.strip())
    title = R.cut(' '.join(re.sub(r'[\x00-\x1f\x7f"\\]', ' ', first).split()).lstrip('#>-*: '), 80) or 'Untitled report'
    quoted = '\n'.join(f'> {l}' if l else '>' for l in lines)  # quoted: a line of the report can never pass for the card's own markup
    return (f'---\nid: NEW\ntitle: "{title}"\ntype: breakfix\nstatus: backlog\nstage: Reported\npriority: P2\n---\n\n## Captured\n{quoted}\n'
            f'_via /backlog-it capture · {T or datetime.date.today()}_\n\n## Scrum Master triage\n- not sorted yet -- triage failed: {why}\n'
            '- filed under Bugs as a bug so the report is kept; type, size and where it belongs are still to be decided\n')

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
    try: rest = [R.arg(a, 'strict') for a in rest]  # ids, a section, key=value: text, as UTF-8
    except UnicodeDecodeError: sys.exit('card: an argument is not UTF-8 text, nothing written')
    def stdin():  # the text to write: never a terminal (it would wait forever), never empty (a lost heredoc)
        if sys.stdin.isatty(): sys.exit('card: pipe the text on stdin')
        try: t = sys.stdin.read()
        except UnicodeDecodeError: sys.exit('card: the text on stdin is not UTF-8, nothing written')
        return t if t.strip() else sys.exit('card: empty text on stdin, nothing written')
    proj, late, extra, lead = opts.get('--project'), None, [], ''
    if verb == 'append' and len(rest) == 2:
        t = stdin(); lock(B); pull(B, proj); p = find(B, rest[0]); write(p, section=rest[1], text=t); what = f'{v(R.fm(p), "id")}: {rest[1]}'; tail = f': {rest[1]}'
    elif verb == 'set' and len(rest) >= 2 and all('=' in a for a in rest[1:]):
        fields = dict(a.split('=', 1) for a in rest[1:])
        if 'id' in fields: sys.exit('card: id is not settable')
        if any(not re.fullmatch(r'[A-Za-z_][\w-]*', k) or re.search(r'[\r\n]', x) for k, x in fields.items()): sys.exit('card: bad key or a newline in a value')
        lock(B); pull(B, proj); p = find(B, rest[0])
        if fields.get('status') == 'done':  # a bundle keeps each card's own point: a part closes only on its own check, the bundle only after its parts
            d, T = R.fm(p), R.tree(R.load(B))
            if (b := R.bundle_of(d, T)): sys.exit(f'card: nothing written -- {R.name(d)} is part of the bundle {R.name(b)} and closes only on its own check: pipe what showed it to `shrink.py part-done {v(d, "id")}` (or take it out with `shrink.py unbundle {v(d, "id")}`)')
            if (still := R.open_parts(d, T)): sys.exit(f'card: nothing written -- {R.name(d)} is a bundle, and {len(still)} of its parts have not passed their own check: ' + ', '.join(R.name(m) for m in still))
        if 'decision' in fields and v(R.fm(p), 'answers'): fields.setdefault('answers', '')  # answers belong to their question: a new or cleared one drops the old
        write(p, {k: (x or None) for k, x in fields.items()})
        change = ', '.join(f'{k}={x}' if x else f'-{k}' for k, x in fields.items())
        what, tail = f'{v(R.fm(p), "id")}: {change}', f': {change}'
    elif verb == 'new' and len(rest) == 1:
        t = stdin(); lock(B); pull(B, proj); cid, p = new(B, rest[0], t); what = f'new {cid}: {v(R.fm(p), "title")}'; lead, tail = 'new: ', ''
    elif verb == 'capture' and len(rest) <= 1:
        if sys.stdin.isatty(): sys.exit('card: pipe the report on stdin')
        t = sys.stdin.buffer.read().decode('utf-8-sig', 'replace')  # a report is kept even when it is not clean UTF-8
        if not t.strip(): sys.exit('card: empty text on stdin, nothing written')
        try: raw = open(rest[0], 'rb').read().decode('utf-8', 'replace') if rest else None
        except OSError: raw = None
        lock(B); late = pull(B, proj, soft=True)
        try: why = triage_fault(B, raw)
        except Exception as e: why = f'the triage output could not be read ({type(e).__name__})'  # nested too deep, or anything else
        if not why: return print('triage ok: nothing written yet -- write the sorted card with `card.py new <epic>`; if it says nothing was written, run `card.py capture` again with no triage file')
        epic, made = bugs_epic(B); extra = [made] if made else []
        cid, p = new(B, epic, unsorted(t, why)); what = f'new {cid}: {v(R.fm(p), "title")}'; lead, tail = 'new: ', f' · not sorted yet -- triage failed: {why}'
    else: sys.exit(__doc__)
    try:
        if late: regen(B, proj); raise NotSent(f'written here, NOT committed and {NS}: {late}')
        sent = 'written here, NOT sent to the shared board: --no-sync leaves the commit and the push to you' if nosync else sync(B, [p] + extra, f'card: {what}'[:72], proj)
    except NotSent as e: sent = NotSent(f'{e} -- the card is saved here; do NOT run this write again; it is sent with the next card write')
    p = _moved.get(p, p)
    # the card by its title with its id is what the person reads; `what` stays the commit subject, unchanged
    print(f'{lead}{R.name(R.fm(p))}{tail} · {sent}')
    if isinstance(sent, NotSent): print(f'card: {sent}', file=sys.stderr); sys.exit(3)

def self_test():
    import tempfile
    T = str(datetime.date.today())
    run = lambda *a, stdin='', ok=True: (lambda r: (r, (r.returncode == 0) == ok or sys.exit(f'{a}: rc={r.returncode} {r.stdout}{r.stderr}')))(
        subprocess.run([sys.executable, __file__, *a], input=stdin, capture_output=True, text=True, encoding='utf-8'))[0]
    g = lambda d, *a: subprocess.run(['git', '-C', d, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false',
                                      '-c', 'core.hooksPath=/dev/null', *a], capture_output=True, text=True, encoding='utf-8', check=True).stdout
    with tempfile.TemporaryDirectory() as t:
        os.environ.update(GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t')
        subprocess.run(['git', 'init', '-q', '--bare', f'{t}/remote.git'], check=True)
        A = f'{t}/a'; subprocess.run(['git', 'clone', '-q', f'{t}/remote.git', A], check=True, capture_output=True)
        os.makedirs(f'{A}/items/EPIC-01-x/stories')
        open(f'{A}/items/EPIC-01-x/epic.md', 'w', encoding='utf-8').write('---\nid: E01\ntitle: X\nstatus: in-progress\n---\n')
        open(f'{A}/items/EPIC-01-x/stories/S1-one.md', 'w', encoding='utf-8').write('---\nid: E01-S1\ntitle: One\nstatus: in-progress\npriority: P2\nstage: Fix ready\ndecision: Ship it?\nanswers: Go -- ship | Wait -- hold\n---\n\n## Answers\n- old\n\n## Notes\nkeep\n')
        g(A, 'add', '-A'); g(A, 'commit', '-qm', 'seed'); g(A, 'push', '-q', 'origin', 'HEAD')
        S1 = f'{A}/items/EPIC-01-x/stories/S1-one.md'
        tricky = '- 50% done, *.md kept, $HOME and `x` -- é ✓\n'  # what printf, globs and shells mangle
        out = run('--board', A, 'append', 'e01-s1', 'Answers', stdin=tricky).stdout
        c = open(S1, encoding='utf-8').read()
        assert tricky.strip() in c and c.index('- old') < c.index('50% done') < c.index('## Notes'), c  # grows its section
        assert f'updated: {T}' in c and 'committed + pushed' in out and 'E01-S1 · ' in open(f'{A}/BOARD.md', encoding='utf-8').read(), out
        assert 'card: E01-S1: Answers' in g(f'{t}/remote.git', 'log', '-1', '--format=%s'), 'not pushed'
        run('--board', A, 'append', 'E01-S1', 'Done (today)', stdin='- shipped\n')
        run('--board', A, 'append', 'E01-S1', 'Done (today)', stdin='- again\n')  # a heading ending in ')' still grows
        assert open(S1, encoding='utf-8').read().count('## Done (today)') == 1 and open(S1, encoding='utf-8').read().rstrip().endswith('- shipped\n- again'), open(S1, encoding='utf-8').read()
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
        before = open(S1, encoding='utf-8').read()
        assert 'matches 0 cards' in run('--board', A, 'set', 'E01-S9', 'status=done', ok=False).stderr
        assert 'not settable' in run('--board', A, 'set', 'E01-S1', 'id=E01-S7', ok=False).stderr and open(S1, encoding='utf-8').read() == before
        B2 = f'{t}/b'; subprocess.run(['git', 'clone', '-q', f'{t}/remote.git', B2], check=True, capture_output=True)  # a stale clone
        card = '---\nid: NEW\ntitle: "Fix the 100% * case"\ntype: breakfix\nstatus: backlog\n---\n\n## Goal\nx\n'
        out = run('--board', A, 'new', 'e01', stdin=card).stdout
        assert '(E01-S2) · ' in out and out.startswith('new: ') and os.path.exists(f'{A}/items/EPIC-01-x/stories/S2-fix-the-100-case.md'), out
        n = R.fm(f'{A}/items/EPIC-01-x/stories/S2-fix-the-100-case.md')
        assert (v(n, 'id'), v(n, 'parent'), v(n, 'created')) == ('E01-S2', 'E01', T), n
        out = run('--board', B2, 'new', 'E01', stdin=card.replace('100% * case', 'other')).stdout  # pulls first: no clash
        assert '(E01-S3) · ' in out and out.startswith('new: '), out
        assert 'needs `id: NEW`' in run('--board', A, 'new', 'E01', stdin='---\ntitle: x\n---\n', ok=False).stderr
        open(f'{A}/items/EPIC-01-x/stories/S9-dup.md', 'w', encoding='utf-8').write('---\nid: E01-S1\n---\n')
        assert 'matches 2 cards' in run('--board', A, 'set', 'E01-S1', 'status=done', ok=False).stderr
        os.remove(f'{A}/items/EPIC-01-x/stories/S9-dup.md')
        head = g(A, 'rev-parse', 'HEAD')
        assert 'NOT sent to the shared board: --no-sync' in run('--board', A, '--no-sync', 'set', 'E01-S1', 'size=S').stdout and g(A, 'rev-parse', 'HEAD') == head
        P = f'{t}/proj'; os.makedirs(f'{P}/.claude'); subprocess.run(['git', 'init', '-q', P], check=True)  # a board inside a project
        subprocess.run(['cp', '-R', f'{A}/items', f'{P}/.claude/backlog-items'], check=True); os.makedirs(f'{P}/.claude/backlog')
        os.rename(f'{P}/.claude/backlog-items', f'{P}/.claude/backlog/items')
        out = run('--board', f'{P}/.claude/backlog', 'set', 'E01-S2', 'status=in-progress').stdout
        assert 'staged, NOT sent to a shared board' in out, out  # staged, never committed
        assert '.claude/backlog/items/EPIC-01-x/stories/S2-fix-the-100-case.md' in g(P, 'diff', '--cached', '--name-only'), 'not staged'
        # --- review fixes ---
        st = lambda f: open(f, encoding='utf-8').read()
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
        open(f'{A}/.git/index.lock', 'w', encoding='utf-8').close()  # another git process holds the index: say so, exit non-zero
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
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8') for _ in range(8)]
        ps += [subprocess.Popen([sys.executable, __file__, '--board', PB, '--no-sync', 'new', 'E01'], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8') for _ in range(4)]
        outs = [q.communicate(f'- line {i}\n' if i < 8 else card)[0] for i, q in enumerate(ps)]
        assert all(f'- line {i}' in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md') for i in range(8)), outs
        ids = [re.search(r'^new: .*\((E01-S\d+)\) · ', o).group(1) for o in outs[8:]]
        assert len(set(ids)) == 4, ids
        import fcntl, time  # the lock is really taken: a writer waits while another holds it
        fd = os.open(f'{PB}/items', os.O_RDONLY); fcntl.flock(fd, fcntl.LOCK_EX)
        q = subprocess.Popen([sys.executable, __file__, '--board', PB, '--no-sync', 'append', 'E01-S1', 'Burst'], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8')
        q.stdin.write('- waited\n'); q.stdin.close(); time.sleep(1.5)
        assert q.poll() is None and '- waited' not in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md'), 'wrote without the lock'
        fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd); q.wait(30)
        assert '- waited' in st(f'{PB}/items/EPIC-01-x/stories/S1-one.md'), q.stderr.read()
        assert not [f for d in (A, PB) for f in os.listdir(f'{d}/items/EPIC-01-x/stories') if f.endswith('.tmp')]
    print('card self-test: OK')

if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']: self_test(); sys.exit(0)
    main(sys.argv[1:])
