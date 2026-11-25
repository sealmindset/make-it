#!/usr/bin/env python3
"""What makes the pile shrink: combine cards into one piece of work, reopen a fix that did not hold, and
close quiet cards nobody asks for. No AI call anywhere here -- facts and written rules.

Usage: shrink.py [--board PATH] [--project NAME] [--no-sync] combine [filter]         (read-only)
       shrink.py [--board PATH] [--project NAME] [--no-sync] bundle <id> <id> [...]   (stdin, below)
       shrink.py [--board PATH] [--project NAME] [--no-sync] part-done <id>           (stdin: what showed that card's own check passed)
       shrink.py [--board PATH] [--project NAME] [--no-sync] unbundle <id>            (a bundle's id: every part goes back; a part's id: that one)
       shrink.py [--board PATH] [--project NAME] [--no-sync] reopen <id>              (stdin: what was seen, word for word)
       shrink.py [--board PATH] [--project NAME] [--no-sync] stamp <id> --by groom|you  (stdin: why it is safe to close, one plain line)
       shrink.py [--board PATH] [--project NAME] [--no-sync] expire [--dry-run [--as-of YYYY-MM-DD]]
       shrink.py --self-test
  --board defaults to $BACKLOG_DIR, then ./.claude/backlog.

combine  lists candidate groups with the facts they share: the same files (a card's `files:`, else file names in
         its text), the same skill (`category:`), cards that already wait on each other. It proposes nothing more
         than that: whether a group has the same root cause or the same goal is the AI's judgement, written down.
         <filter> as for plan (a status, a priority, a category, an epic); a single card's id shows only the
         groups that card is in. Writes nothing.
bundle   makes ONE card for one piece of work (one lane, one pull request) out of the cards named. On stdin:
             title: <the bundle's title>
             ground: same file | same root cause | same goal
             why: <the evidence, in a line>
             <id>: <that card's own check -- how we will know its point is met>     (one line per card)
         The bundle card lists every part with its own check (`bundles: [ids]`); each part is kept whole and only
         marked `bundledIn: <bundle id>`. From then on every helper counts the bundle as one thing to do.
part-done  closes one part on its own check. A part never closes any other way, and the bundle closes only
         after every part has.
unbundle puts the parts back in line, each file byte for byte as it was; the bundle card is kept, closed.
reopen   puts a closed card back in line with the person's words kept (`reopened: <date>`).
stamp    marks a card `expires: ok` (with `expires_why:`, `expires_by:` and a print of the words that were judged).
         The judging is not done here: groom's judge, or the owner's pick, decides, and this only records it. It
         refuses a card a hard rule protects. No mark, never: `expire` closes nothing that is not marked.
expire   closes the marked cards status.py's written rule (`expiry`) allows, after EXPIRE_DAYS quiet days; every hard
         rule still applies on top of the mark. --dry-run lists what would close, what closes soon or later, and why
         the rest are kept, and writes nothing; with --as-of it works that out for a later day (dry run only).
ponytail: if two clones give a new bundle card and another new card the same id, card.py renumbers ours and names
the parts that still point at the old id ("check them"): re-run `bundle` then; nothing is lost meanwhile.
Writes go through card.py's lock, pull and sync: the line printed ends with what happened, and exit 3 means
saved here but not sent (do not run it again). Any other non-zero exit = nothing written.
"""
import collections, datetime, importlib.util, os, re, sys

_bin = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
def _load(name, f):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_bin, f))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
C, S, P = _load('card', 'card.py'), _load('status_board', 'status.py'), _load('scope_board', 'scope.py')
R, v = C.R, C.R.v

BUNDLE_MAX = 5  # the most cards one bundle holds: past five, a reviewer can no longer hold each card's own check in mind, and one slip holds up all of them
SITTING = 8     # the most work one bundle holds, in points (XS 1, S 2, M 3, L 5, XL 8; no size counts as M): about one large card, which is what one lane finishes in one sitting
POINTS = {'XS': 1, 'S': 2, 'M': 3, 'L': 5, 'XL': 8}
GROUNDS = ('same file', 'same root cause', 'same goal')  # the owner's three grounds for combining (2026-11-24)
SHOW = 8        # cards listed per group, and groups per kind, before "+N more": enough to judge, short enough to read
EVERYWHERE = {'readme.md', 'changelog.md', 'claude.md', 'todo.md', 'version', 'content_manifest', 'board.md', 'plan.md', 'groom-plan.md',
              'handoff.md', 'epic.md', 'skill.md', 'design.md'}  # release bookkeeping and board files every change touches: sharing one is no reason to combine
FILE = re.compile(r'(?<![\w/.-])((?:[\w.-]+/)*[\w.-]+\.(?:py|md|sh|json|ya?ml|tsx?|jsx?|toml|css|html|sql|ps1|tf))(?![\w/-])')

def no(msg): sys.exit(f'shrink: nothing written -- {msg}')
def full(d): return R.name(d, 200)  # a card on a card: its whole title with its id

def mark(p, key, val=None):
    """Add (`val`) or take away (None) one frontmatter line and touch nothing else -- not even `updated:` -- so
    taking it away again gives the file back byte for byte."""
    raw = open(p, 'rb').read()
    m = re.match(rb'(?:\xef\xbb\xbf)?---\r?\n.*?(\r?\n)---', raw, re.S)
    if not m: sys.exit(f'shrink: no frontmatter in {p}')
    nl, cut = m.group(1), m.start(1)
    head = re.sub(re.escape(nl + f'{key}:'.encode()) + rb'[^\r\n]*', b'', raw[:cut], count=1)
    if val is not None: head += nl + f'{key}: {val}'.encode()
    tmp = f'{p}.{os.getpid()}.tmp'
    with open(tmp, 'wb') as f: f.write(head + raw[cut:])
    os.replace(tmp, p)

def send(B, paths, msg, proj, nosync):
    """Regenerate, commit and push through card.py's own sync: (what happened, the exit code)."""
    if nosync: return 'written here, NOT sent to the shared board: --no-sync leaves the commit and the push to you', 0
    try: return C.sync(B, paths, msg[:72], proj), 0
    except C.NotSent as e: return f'{e} -- saved here; do NOT run this again; it is sent with the next card write', 3

def board(B):
    cards = R.load(B); T = R.tree(cards)
    return cards, T, {v(d, 'id').upper(): p for p, d in cards.items()}

def files_of(p, d):
    """{file name: (the path as written, 'files' or 'text')}: the files a card would change, from its `files:`
    field, else the file names its text mentions. ponytail: files are matched by name, so two files of one name
    in different folders count as the same; `files:` with full paths is what makes this exact."""
    out = {}
    try: body = open(p, encoding='utf-8-sig').read().split('\n---', 1)[-1]
    except (OSError, UnicodeDecodeError): body = ''
    for src, names in (('text', FILE.findall(body)), ('files', [x.strip(' `"\'') for x in v(d, 'files').strip('[] ').split(',') if x.strip()])):
        for n in names:
            k = os.path.basename(n).lower()
            if k and k not in EVERYWHERE and (src == 'files' or len(n) >= len(out.get(k, ('',))[0])): out[k] = (n, src)
    return out

def combine(B, flt, proj, T=None):
    T = T or datetime.date.today()
    cards, tree, where = board(B); byid = tree[0]
    try: named = P.scope(B, flt)['in_filter']  # open leaf cards nobody has started; a part of a bundle is already out
    except LookupError as e: sys.exit(f'shrink: {e}')
    focus = flt.strip().upper() if P.ID.fullmatch(flt.strip()) and named == [flt.strip().upper()] else ''
    pool = [i for i in (P.scope(B, '')['in_filter'] if focus else named) if not R.waiting(byid[i]) and not R.parts(byid[i])]
    crit = lambda i: bool(R.warn(byid[i]))
    files = {i: files_of(where[i], byid[i]) for i in pool}
    apart = collections.Counter()
    def split(ids):  # a high-stakes card never goes with one that is not: each side is its own group, if it still has two cards
        a, b = [i for i in ids if not crit(i)], [i for i in ids if crit(i)]
        if a and b: apart.update(b)
        return [g for g in (a, b) if len(g) > 1]
    by_file = collections.defaultdict(set)
    for i in pool:
        for k in files[i]: by_file[k].add(i)
    sets = {tuple(g) for ids in by_file.values() for g in split(sorted(ids, key=P.key))}
    same = {g: sorted(set.intersection(*(set(files[i]) for i in g))) for g in sets}  # each set of cards -> every file all of them name
    by_cat = collections.defaultdict(list)
    for i in pool:
        if v(byid[i], 'category'): by_cat[v(byid[i], 'category').lower()].append(i)
    waits, chain = [(i, leaf) for i in pool for leaf, _, _ in R.needs(i, tree) if leaf in pool and crit(i) == crit(leaf)], []  # a wait across the high-stakes line joins nothing
    for a, b in waits:  # cards joined by a wait, however long the chain
        hit = [g for g in chain if a in g or b in g]
        for g in hit: chain.remove(g)
        chain.append(set().union({a, b}, *hit))
    groups = []  # (heading, line, ids, per-card note)
    for g, ks in sorted(same.items(), key=lambda x: (-len(x[1]), len(x[0]), x[0])):
        shown = sorted(files[g[0]][k][0] if files[g[0]][k][1] == 'files' else max((files[i][k][0] for i in g), key=len) for k in ks)
        note = lambda i, ks=ks: ' · named in its text' if any(files[i][k][1] == 'text' for k in ks) else ' · from its `files:`'
        groups.append(('Same file', ', '.join(shown), list(g), note))
    for cat, ids in sorted(by_cat.items(), key=lambda x: (len(x[1]), x[0])):
        groups += [('Same skill', cat, g, lambda i: '') for g in split(ids)]
    for g in sorted(chain, key=lambda g: sorted(g, key=P.key)):
        for part in split(sorted(g, key=P.key)):
            groups.append(('Wait on each other', 'a chain', part, lambda i, part=part: ''.join(f' · waits on {R.name(byid[b])}' for a, b in waits if a == i and b in part)))
    if focus: groups = [g for g in groups if focus in g[2]]
    out = [f"COMBINE -- {proj} · {T} · {len(pool)} cards could be combined (open, not started, not in a bundle)" + (f' · only the groups {R.name(byid[focus])} is in' if focus else '')]
    n = 0
    for head in ('Same file', 'Same skill', 'Wait on each other'):
        mine = [g for g in groups if g[0] == head]
        if not mine: continue
        out.append(head)
        for _, line, ids, note in mine[:SHOW]:
            n += 1; cap = len(ids) if flt.strip() else SHOW
            pts = sum(POINTS.get(v(byid[i], 'size').upper(), 3) for i in ids)
            fits = '' if len(ids) <= BUNDLE_MAX and pts <= SITTING else f' · too big for one bundle ({len(ids)} cards, {pts} points): pick from it'
            out.append(f"  {n}. {line} -- {len(ids)} cards" + (' · all high-stakes: the bundle would be held too' if crit(ids[0]) else '') + fits)
            out += [f"     {R.name(byid[i])} · {v(byid[i], 'priority') or 'no priority'} {v(byid[i], 'size') or '—'}{note(i)}" for i in ids[:cap]]
            out += [f'     +{len(ids) - cap} more (`combine {line}` lists them)'] * (len(ids) > cap)
        out += [f'  +{len(mine) - SHOW} more groups (give a filter to see fewer cards at a time)'] * (len(mine) > SHOW)
    if not n: out.append('  nothing to combine: no two of these cards share a file, a skill, or a wait')
    if apart: out += ['Kept apart'] + [f"  {R.name(byid[i])} -- high-stakes: left out of {k} group{'s' * (k != 1)}, because a high-stakes card is never bundled with a card that is not"
                                       for i, k in sorted(apart.items(), key=lambda x: P.key(x[0])) if not focus or i == focus]
    out.append(f'A bundle holds at most {BUNDLE_MAX} cards and one sitting ({SITTING} points: XS 1, S 2, M 3, L 5, XL 8; no size counts as M).')
    out.append('Same root cause and same goal are for the AI to judge from these groups, with its reason written down. Nothing combines without your pick.')
    return '\n'.join(out)

def bundle(B, ids, text, proj, nosync, T=None):
    T = T or datetime.date.today()
    cards, tree, where = board(B); byid = tree[0]
    ids = list(dict.fromkeys(i.upper() for i in ids))
    spec = {m.group(1).lower() if m.group(1).lower() in ('title', 'ground', 'why') else m.group(1).upper(): m.group(2).strip()
            for l in text.splitlines() if (m := re.match(r'\s*([A-Za-z]+|E\d+(?:-S\d+)+)\s*:\s*(\S.*)$', l))}
    if len(ids) < 2: no('a bundle needs at least 2 cards')
    if len(ids) > BUNDLE_MAX: no(f'a bundle holds at most {BUNDLE_MAX} cards, and {len(ids)} were named: split them, most alike first')
    for i in ids:
        d = byid.get(i)
        if not d or '/stories/' not in where[i] or i in tree[1]: no(f'{i} is not a single card on this board (an epic, a card with cards under it, or not here)')
        why = ('it is done' if v(d, 'status') == 'done' else f"work on it has started ({v(d, 'status')})" if v(d, 'status') not in ('backlog', 'ready', 'designing')
               else 'it is a bundle itself' if R.parts(d) else f'it is already part of {full(b)}' if (b := R.bundle_of(d, tree)) else 'it waits on your answer' if R.waiting(d) else '')
        if why: no(f'{full(d)} cannot be bundled: {why}')
    hot = [i for i in ids if R.warn(byid[i])]
    if hot and len(hot) < len(ids):
        cold = next(i for i in ids if i not in hot)
        no(f'{full(byid[hot[0]])} is high-stakes and {full(byid[cold])} is not: a high-stakes card is never bundled with a card that is not, so its gate is never lost')
    if spec.get('ground') not in GROUNDS: no('say the ground on a line `ground: ...`: same file, same root cause, or same goal')
    if not spec.get('why'): no('say why these belong together, with the evidence, on a line `why: ...`')
    if not spec.get('title'): no('give the bundle a title on a line `title: ...`')
    for i in ids:
        if not spec.get(i): no(f'no check given for {full(byid[i])}: each card keeps its own check -- add a line `{i}: how we will know its point is met`')
    pts = sum(POINTS.get(v(byid[i], 'size').upper(), 3) for i in ids)
    if pts > SITTING: no(f'together these cards are more than one sitting ({pts} points; the limit is {SITTING}: XS 1, S 2, M 3, L 5, XL 8, no size counts as M)')
    bug = [i for i in ids if v(byid[i], 'type') == 'breakfix']
    home = cards[os.path.join(os.path.dirname(os.path.dirname(where[(bug or ids)[0]])), 'epic.md')]
    cats = {v(byid[i], 'category') for i in ids}
    size = next(k for k, x in POINTS.items() if x >= pts)
    fm = [('id', 'NEW'), ('title', '"' + ' '.join(spec['title'].replace('"', "'").split()) + '"'), ('type', 'breakfix' if bug else 'story'), ('status', 'backlog')] + [('stage', 'Reported')] * bool(bug) + [
          ('category', cats.pop() if len(cats) == 1 else v(byid[ids[0]], 'category')), ('priority', min(v(byid[i], 'priority') or 'P9' for i in ids).replace('P9', '')), ('size', size)] + [
          ('bundles', '[' + ', '.join(ids) + ']'), ('ground', spec['ground'])]
    body = (f"\n## Goal\nOne piece of work -- one lane, one pull request -- that does these {len(ids)} cards together, without watering any of them down:\n"
            "each keeps its own check below and closes only when that check passes.\n\n"
            f"## Why together\n- ground: {spec['ground']}\n- {spec['why']}\n\n## Parts\n" + ''.join(f'- [ ] {full(byid[i])} -- check: {spec[i]}\n' for i in ids)
            + "\n## Definition of done\nEvery part's own check has passed, each recorded with `part-done`; then the bundle closes like any card\n(released, tests pass). `unbundle` puts the parts back in line as they were.\n")
    bid, bp = C.new(B, v(home, 'id'), '---\n' + ''.join(f'{k}: {x}\n' for k, x in fm if x) + '---\n' + body, T)
    for i in ids: mark(where[i], 'bundledIn', bid)
    sent, rc = send(B, [bp] + [where[i] for i in ids], f"card: new {bid}: a bundle of {', '.join(ids)}", proj, nosync)
    print(f"new: {full(R.fm(bp))}, a bundle of {len(ids)}: {', '.join(R.name(byid[i]) for i in ids)} · {sent}")
    return rc

def tick(bp, cid, to):  # the part's line on its bundle card: `- [ ]` -> `- [x]` (its check passed) or `- [out <date>]`
    txt = open(bp, encoding='utf-8', newline='').read()
    new = re.sub(rf'^- \[[^\]]*\] (?=.*\({re.escape(cid)}\) -- check: )', f'- [{to}] ', txt, count=1, flags=re.M | re.I)
    with open(bp, 'w', encoding='utf-8', newline='') as f: f.write(new)

def part_done(B, cid, text, proj, nosync, T=None):
    T = T or datetime.date.today()
    cards, tree, where = board(B); d = tree[0].get(cid.upper())
    b = R.bundle_of(d, tree) if d else None
    if not b: no(f"{full(d) if d else cid} is not an open part of an open bundle: there is no check of its own to record")
    p, bp = where[cid.upper()], where[v(b, 'id').upper()]
    check = (re.search(rf'^- \[[^\]]*\] .*\({re.escape(v(d, "id"))}\) -- check: (.+)$', open(bp, encoding='utf-8').read(), re.M) or [0, 'not written on the bundle'])[1]
    C.write(p, {'status': 'done'}, f'Check passed ({T})', f'- its own check, as part of {full(b)}: {check}\n- what showed it:\n' + '\n'.join(f'  > {l}' for l in text.strip('\n').split('\n')), T)
    tick(bp, v(d, 'id'), 'x'); C.write(bp, {}, T=T)
    left = len(R.open_parts(b, R.tree(R.load(B)))); n = len(R.parts(b))
    sent, rc = send(B, [p, bp], f"card: {v(d, 'id')}: its own check passed (part of {v(b, 'id')})", proj, nosync)
    print(f"{R.name(d)}: its own check passed, closed · " + (f"{left} of {n} parts of {R.name(b)} still open" if left else
          f"every part of {R.name(b)} has passed its own check: the bundle closes when its pull request is released with passing tests") + f' · {sent}')
    return rc

def unbundle(B, cid, proj, nosync, T=None):
    T = T or datetime.date.today()
    cards, tree, where = board(B); d = tree[0].get(cid.upper())
    if not d: no(f'{cid} matches no card on this board')
    b = R.bundle_of(d, tree)
    if b and len(R.parts(b)) > 2:  # one part out; the bundle keeps the rest
        bp, p = where[v(b, 'id').upper()], where[cid.upper()]
        mark(p, 'bundledIn'); tick(bp, v(d, 'id'), f'out {T}')
        rest = [i for i in R.parts(b) if i != cid.upper()]
        C.write(bp, {'bundles': '[' + ', '.join(rest) + ']'}, f'Taken out ({T})', f'- {full(d)} went back in line as it was', T)
        sent, rc = send(B, [p, bp], f"card: {v(d, 'id')}: taken out of the bundle {v(b, 'id')}", proj, nosync)
        print(f"Took {R.name(d)} out of {R.name(b)}: it is back in line as it was · {len(rest)} parts stay in the bundle · {sent}")
        return rc
    b = b or d  # a part of a bundle of two: a bundle of one is no bundle, so the whole bundle goes
    if not R.parts(b): no(f'{full(d)} is not a bundle and not part of one')
    if v(b, 'status') == 'done': no(f'{full(b)} is already closed')
    back = R.open_parts(b, tree); bp = where[v(b, 'id').upper()]
    for m in back: mark(where[v(m, 'id').upper()], 'bundledIn')
    C.write(bp, {'status': 'done', 'closed_as': 'unbundled', 'pin': None}, f'Un-bundled ({T})',
            '- every open part went back in line as it was; a part whose own check had passed stays closed\n- nothing was deleted: this card is kept as the record', T)
    sent, rc = send(B, [bp] + [where[v(m, 'id').upper()] for m in back], f"card: {v(b, 'id')}: un-bundled", proj, nosync)
    print(f"Un-bundled {R.name(b)}: " + (', '.join(R.name(m) for m in back) + (' is back in line as it was' if len(back) == 1 else ' are back in line as they were') if back else 'no part was still open')
          + f'; the bundle card is kept, closed · {sent}')
    return rc

def reopen(B, cid, text, proj, nosync, T=None):
    T = T or datetime.date.today()
    cards, tree, where = board(B); d = tree[0].get(cid.upper())
    if not d: no(f'{cid} matches no card on this board')
    if v(d, 'status') != 'done': no(f'{full(d)} is not closed, so there is nothing to reopen -- add what was seen with `card.py append {v(d, "id")} "Seen in use"`')
    if R.parts(d): no(f'{full(d)} is a bundle: reopen the card inside it whose fix did not hold')
    bug, p = v(d, 'type') == 'breakfix', where[cid.upper()]
    how = {'shipped-tests-pass': 'as shipped (its tests passed; no real run confirmed it)', 'expired': 'by the board, as a quiet card nobody asked for', '': 'as done'}.get(v(d, 'closed_as'), f"as {v(d, 'closed_as')}")
    note = '\n'.join(f'> {l}' if l else '>' for l in text.replace('\r\n', '\n').strip('\n').split('\n'))  # quoted, line for line: the person's words
    note += f"\n- it was closed {how}, last changed {v(d, 'updated') or 'on an unknown date'}" + (f"; the fix was pull request {v(d, 'pr')}, which no longer closes this card" if v(d, 'pr') else '')
    C.write(p, {'status': 'backlog', 'stage': 'Reported' if bug else None, 'closed_as': None, 'pr': None, 'checkAfter': None, 'reopened': str(T)}, f'Reopened ({T})', note, T)
    b = tree[0].get(v(d, 'bundledIn').upper()); b = b if b and v(b, 'status') != 'done' and cid.upper() in R.parts(b) else None
    paths = [p]
    if b:  # a part of a bundle that is still open: it is open inside the bundle again, and its own check must pass again
        bp = where[v(b, 'id').upper()]; tick(bp, v(d, 'id'), ' '); C.write(bp, {}, T=T); paths.append(bp)
    sent, rc = send(B, paths, f"card: {v(d, 'id')}: reopened", proj, nosync)
    print(f"Reopened: {R.name(d)} is " + (f"back in its bundle {R.name(b)}, open again: its own check must pass again" if b else f"back in line ({'a bug at Reported' if bug else 'in the backlog'})")
          + f", with what was seen kept on it · {sent}")
    return rc

def stamp(B, cid, by, text, proj, nosync, T=None):
    """Record a judge's mark that a card is safe to close when quiet. The judgement is groom's judge's or the owner's;
    here it is only written down, with a print of the words judged, so a later edit clears it."""
    f = S.facts(B, T); d = f['tree'][0].get(cid.upper()); why = ' '.join(text.split())
    if not d: no(f'{cid} matches no card on this board')
    if by not in ('groom', 'you'): no('say who judged it: `--by groom` (groom\'s judge) or `--by you` (the owner\'s pick)')
    if not why: no('say why it is safe to close, in one plain line on stdin')
    p = next(q for q, x in f['cards'].items() if x is d)
    kept = S.expiry(f)['kept'].get(p, '')
    if kept and not kept.startswith(('not marked', 'marked', 'no date')): no(f'{full(d)} can never close by itself: {kept}')  # a hard rule protects it: a mark would change nothing, and would mislead
    C.write(p, {'expires': 'ok', 'expires_why': why, 'expires_by': by, 'expires_of': S.stamp_of(open(p, encoding='utf-8-sig').read())}, T=T)
    sent, rc = send(B, [p], f"card: {v(d, 'id')}: marked safe to close when quiet (by {by})", proj, nosync)
    print(f"Marked safe to close when quiet: {R.name(d)} · judged by {by} · it closes after {S.EXPIRE_DAYS} quiet days unless a hard rule or an edit stops it · {sent}")
    return rc

def expire(B, dry, said, proj, nosync, T=None):
    f = S.facts(B, T); T = f['T']; ex = S.expiry(f); c = f['cards']
    days = lambda k: f"{k} day{'s' * (k != 1)}"
    out = [f"EXPIRE -- {said} · {T}" + (' · dry run, nothing written' if dry else '')]
    out.append(f"{'Would close' if dry else 'Closed'} {len(ex['close'])} card{'s' * (len(ex['close']) != 1)}: " + (f"marked safe to close, quiet for {S.EXPIRE_DAYS} days or more, with nothing waiting" if ex['close'] or ex['soon'] or ex['later'] else 'no card is marked as safe to close yet: groom marks them'))
    out += [f"  {R.name(c[p])} · quiet {days(q)}" for p, q in ex['close']]
    if ex['soon']: out += [f"Closing within {S.EXPIRE_WARN} days: {len(ex['soon'])}"] + [f"  {R.name(c[p])} · quiet {days(q)}, closes in {days(k)}" for p, q, k in ex['soon']]
    later = sorted(ex['later'], key=lambda x: -x[1])  # the kind of card that expires, not quiet long enough yet: the quietest three, so nothing closes as a surprise
    if later: out += [f"Would close later, if they stay quiet: {len(later)}"] + [f"  {R.name(c[p])} · quiet {days(q)}" for p, q in later[:3]] + [f'  +{len(later) - 3} more'] * (len(later) > 3)
    kept = collections.Counter(ex['kept'].values())
    out += [f"Kept, whatever their age: {sum(kept.values())}"] + [f'  {k:>3} · {why}' for why, k in kept.most_common()]
    if not dry:
        for p, q in ex['close']:
            C.write(p, {'status': 'done', 'closed_as': 'expired', 'pin': None}, f'Expired ({T})',
                    f"- closed by the board: quiet for {days(q)} (no change to this card, no pull request, no card mentioning it), with no report behind it, no person named on it, and no card waiting on it\n"
                    f"- marked safe to close by {v(c[p], 'expires_by')}: {v(c[p], 'expires_why')}\n"
                    f"- nothing was deleted. To bring it back: `/backlog-it reopen {v(c[p], 'id')} <why it is needed>`", T)
        if ex['close']:
            sent, rc = send(B, [p for p, _ in ex['close']], f"expire: closed {len(ex['close'])} quiet card{'s' * (len(ex['close']) != 1)}", proj, nosync)
            print('\n'.join(out + [sent])); return rc
    print('\n'.join(out)); return 0

def main(args):
    opts = {}
    for k in ('--board', '--project'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'shrink: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    flag = lambda k: k in args and not args.remove(k)
    for k in ('--by', '--as-of'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args): sys.exit(f'shrink: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    nosync, dry = flag('--no-sync'), flag('--dry-run')
    asof = S.day(opts['--as-of']) if '--as-of' in opts else None
    if '--as-of' in opts and (not dry or not asof): sys.exit('shrink: nothing written -- --as-of takes a date (YYYY-MM-DD) and is for `expire --dry-run` only: a real expire always uses today')
    B = os.path.abspath(os.path.expanduser(opts.get('--board') or os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'shrink: no items/ folder in {B}')
    proj = opts.get('--project')
    home = os.path.dirname(B); home = os.path.dirname(home) if os.path.basename(home) == '.claude' else home  # <repo>/.claude/backlog -> the repo's name, as regen-board says it
    said = R.arg(proj or (open(f'{B}/.project', encoding='utf-8').read().strip() if os.path.exists(f'{B}/.project') else os.path.basename(home)))
    verb, rest = (args[0], [R.arg(a) for a in args[1:]]) if args else ('', [])
    def stdin():
        if sys.stdin.isatty(): sys.exit('shrink: pipe the text on stdin')
        try: t = sys.stdin.read()
        except UnicodeDecodeError: sys.exit('shrink: the text on stdin is not UTF-8, nothing written')
        return t if t.strip() else sys.exit('shrink: empty text on stdin, nothing written')
    if verb == 'combine': return print(combine(B, ' '.join(rest), said))
    if verb == 'expire' and not rest and dry: return expire(B, True, said, proj, True, asof)
    if verb == 'bundle' and rest: t = stdin(); C.lock(B); C.pull(B, proj); rc = bundle(B, rest, t, proj, nosync)
    elif verb == 'part-done' and len(rest) == 1: t = stdin(); C.lock(B); C.pull(B, proj); rc = part_done(B, rest[0], t, proj, nosync)
    elif verb == 'unbundle' and len(rest) == 1: C.lock(B); C.pull(B, proj); rc = unbundle(B, rest[0], proj, nosync)
    elif verb == 'stamp' and len(rest) == 1: t = stdin(); C.lock(B); C.pull(B, proj); rc = stamp(B, rest[0], opts.get('--by', ''), t, proj, nosync)
    elif verb == 'reopen' and len(rest) == 1: t = stdin(); C.lock(B); C.pull(B, proj); rc = reopen(B, rest[0], t, proj, nosync)
    elif verb == 'expire' and not rest: C.lock(B); C.pull(B, proj); rc = expire(B, False, said, proj, nosync)
    else: sys.exit(__doc__)
    sys.exit(rc)

def self_test():
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        for raw in (b'---\nid: E01-S1\ntitle: x\n---\n\n## Goal\n---\nbody\n', b'\xef\xbb\xbf---\r\nid: E01-S1\r\nupdated: 2020-01-01\r\n---\r\nbody\r\n'):
            p = f'{t}/c.md'; open(p, 'wb').write(raw)
            mark(p, 'bundledIn', 'E01-S9'); got = open(p, 'rb').read()
            assert b'bundledIn: E01-S9' in got.split(b'---')[1] and got != raw and v(R.fm(p), 'bundledIn') == 'E01-S9', got
            mark(p, 'bundledIn'); assert open(p, 'rb').read() == raw, open(p, 'rb').read()  # byte for byte, line endings and BOM kept
            mark(p, 'bundledIn', 'E01-S9'); mark(p, 'bundledIn', 'E01-S8'); assert open(p, 'rb').read().count(b'bundledIn') == 1  # marked again: one line, the new one
        os.makedirs(f'{t}/items/EPIC-01-x/stories')
        open(f'{t}/items/EPIC-01-x/epic.md', 'w', encoding='utf-8').write('---\nid: E01\ntitle: X\ntype: epic\nstatus: in-progress\n---\n')
        for n, kv in ((1, 'size: S\nfiles: [src/a.py]\n'), (2, 'size: S\n'), (3, 'size: XL\n')):
            open(f'{t}/items/EPIC-01-x/stories/S{n}.md', 'w', encoding='utf-8').write(f'---\nid: E01-S{n}\ntitle: Card {n}\ntype: story\nstatus: backlog\ncategory: x\n{kv}---\nSee `lib/src/a.py` and README.md.\n')
        out = combine(t, '', 't')
        assert 'Same file\n  1. src/a.py -- 3 cards · too big for one bundle (3 cards, 12 points)' in out and 'Card 1 (E01-S1) · no priority S · from its `files:`' in out and 'Card 2 (E01-S2) · no priority S · named in its text' in out, out
        assert 'README' not in out and 'Same skill\n  2. x -- 3 cards' in out, out  # a file every change touches is no ground
        assert sorted(files_of(f'{t}/items/EPIC-01-x/stories/S2.md', {})) == ['a.py'] and SITTING == POINTS['XL'] and 2 <= BUNDLE_MAX, 'limits'
    print('shrink self-test: OK')

if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']: self_test(); sys.exit(0)
    main(sys.argv[1:])
