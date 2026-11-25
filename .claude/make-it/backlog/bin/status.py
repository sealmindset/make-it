#!/usr/bin/env python3
"""Print where the board stands: in flight, bundles, up next, burn-down + forecast, needs you, drift,
epics, and cycle time. Read-only, no AI call -- the same board gives the same answer.

Usage: status.py [board_dir] [--project NAME] [--needs-you]
       status.py [board_dir] [--project NAME] --first [--repo PATH] [--lane-cap N] [--seen]
       status.py --self-test
  --first  the first screen: the one thing to do next (a written rule, with its choices), only what
           needs you, what changed since you last looked, and one trend line. --repo is the code repo
           whose open pull requests `gh` lists (without it, or without gh, those steps are skipped and
           said so). --seen records this look in <board>/.last-seen.json (kept out of the board's git).
  Dates come from the board's git history (when a card went done, and when it last changed). With
  no git history, from each card's created: and updated:.
  This file also holds the rule for which quiet cards close by themselves (`expiry`); `shrink.py
  expire` is what closes them.
"""
import datetime, importlib.util, json, os, re, statistics, subprocess, sys

_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
v, D = R.v, datetime.timedelta
WEEKS, STALL, LANE, TOP = 4, 14, 2, 5  # ponytail: fixed window, stall thresholds (work / a lane) and list cap; flags if anyone needs them
# The first screen's rule, as named numbers (owner interview 2026-11-24):
PR_STALL = 2      # days an open pull request may sit unchanged before it counts as stalled: lanes work in hours, so two quiet days means nobody is on it (same as LANE)
PLAN_STALE = 0.5  # the plan is stale once more than this share of the cards that can start are not in it: past half, it no longer describes the board
GROW_WEEKS = 2    # weeks running with more cards opened than closed before a groom is the next thing: one bad week is noise, two is a trend
GROOM_AGE = 14    # days after which the last groom is too old to trust, whatever the trend: its order was made for a board two weeks gone
GROOM_REST = 7    # days a groom is left alone even while the pile grows, so the board never answers "groom" twice in the same week
SIT = (3, 5)      # held cards brought to a weekly sitting: three when questions also wait, five at most, so the screen stays short enough to read
# Expiry (owner's choice, 2026-11-24: "Yes, after 30 days, never a safety one"):
EXPIRE_DAYS = 30  # quiet days after which a card nobody asks for closes itself: a month with no change, no pull request and no mention means nobody is asking
EXPIRE_WARN = 7   # the first screen counts the cards that will close within this many days: a week's notice, so one look a week is enough to save one
SAFETY = r'secur|secret|credential|password|token|\bkey\b|leak|vulnerab|\bCVE|auth|permission|privacy|personal|data loss|los\w* (?:\w+ )?data|delet|destroy|overwrit|corrupt|wrong|untrue|false|mislead|\blie[sd]?\b|\bpay|\bbill|money|\bgate|guard|\bscan|fail'  # words in a title or category that mark a card as one that can hurt someone (lose data, leak a secret, send something wrong, say something untrue) or as a gate or failed check: it never expires
MARK = '.last-seen.json'  # when the owner last opened the first screen, and what the board held then

def day(s):
    try: return datetime.date.fromisoformat(s.strip())
    except ValueError: return None

def history(B):
    """({card path: {added, added_done, done, touched}}, first date, source)."""
    git = lambda *a: subprocess.run(['git', '-C', B, *a], capture_output=True, text=True, encoding='utf-8', errors='replace')
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
    TREE = R.tree(cards)  # what each card waits on, by the board's one rule (regen-board.needs)
    leaf = {p: d for p, d in cards.items() if '/stories/' in p}
    op = {p: d for p, d in leaf.items() if v(d, 'status') != 'done'}
    title = lambda d: v(d, 'title').strip('"')
    opened = lambda p, d: day(v(d, 'created')) or day(h(p).get('added', '')) or datetime.date.min
    # last change: the later of git's last commit and the card's own updated: (a lane's write may not be committed yet)
    last = lambda p, d: max(filter(None, (day(h(p).get('touched', '')), day(v(d, 'updated')))), default=None) or opened(p, d)
    idle = lambda p, d: max(0, (T - last(p, d)).days)  # an updated: written in UTC can be a day ahead of local time
    def done_on(p, d):  # the last commit that set it done; else (or if it entered git done) its own updated:
        x = h(p)
        return day(x['done']) if x.get('done') and not x.get('added_done') else day(v(d, 'updated')) or datetime.date.min
    wrap = lambda d: bool(R.parts(d))  # a bundle card wraps cards that are already counted: it is never opened or closed in the numbers
    dn = {p: done_on(p, d) for p, d in leaf.items() if v(d, 'status') == 'done' and not wrap(d)}
    seen = [p for p in leaf if not h(p).get('added_done') and not wrap(leaf[p])]  # a card that entered git already done (an import) was opened and closed before
    rows = []
    for w in range(WEEKS):
        end = T - D(days=7 * w); start = end - D(days=7)
        if first and end < first: break
        rows.append((end, sum(start < opened(p, leaf[p]) <= end for p in seen),
                     sum(start < dn[p] <= end for p in seen if p in dn),
                     sum(opened(p, d) <= end and not (p in dn and dn[p] <= end) for p, d in leaf.items() if not wrap(d))))
    bug = lambda d: v(d, 'type') == 'breakfix'
    pick = lambda pred: sorted((p for p, d in op.items() if pred(d)), key=lambda p: -idle(p, op[p]))
    flight = {k: pick(lambda d: R.bucket(d) == k) for k in ('Now fixing', 'Shipping')}  # the board's own lines
    flight['Other work'] = pick(lambda d: not bug(d) and not R.bucket(d) and v(d, 'status') == 'in-progress')
    epics = {os.path.dirname(p): d for p, d in cards.items() if p.endswith('/epic.md')}
    kids = lambda e: [p for p in leaf if os.path.dirname(os.path.dirname(p)) == e]
    next_bugs = []  # the board's own Next up, per bug epic
    for e in sorted(epics):
        if any(bug(leaf[p]) for p in kids(e)):
            short = R.next_up([leaf[p] for p in kids(e)], TREE)
            next_bugs += [p for p in kids(e) if v(leaf[p], 'id').split('-')[-1] == short]
    parents = {v(d, 'parent').upper() for d in cards.values()}
    can = sorted((p for p, d in op.items() if not bug(d) and v(d, 'status') in ('backlog', 'ready')
                  and v(d, 'id').upper() not in parents and not R.blocked(d, TREE)),
                 key=lambda p: (v(op[p], 'priority') or 'P9', opened(p, op[p]), p))
    plan, pf = None, os.path.join(B, 'PLAN.md')
    if os.path.exists(pf):
        txt = open(pf, encoding='utf-8').read(); pd = day((re.search(r'\d{4}-\d{2}-\d{2}', txt.split('\n', 1)[0]) or [''])[0])
        cand = [p for p, d in op.items() if v(d, 'status') in ('backlog', 'ready', 'designing') and v(d, 'id').upper() not in parents and not R.bundle_of(d, TREE)]
        def wave_ids(w):
            """The cards a wave or bullet line is about, not the ones its reason mentions. The older form leads
            with bare ids (`· E01-S8 · title -- why`, `- E01-S8 -- why`); the plain form names each card
            `Title (E01-S8)` up to the first ` -- ` that follows an id."""
            head = w.split(' -- ')[0]
            old = re.findall(r'(?:· |^\s*- [^\w(]*?)(E\d+(?:-S\d+)?)\b', head)
            if old: return [i.upper() for i in old]
            m = re.match(r'(.*?\(E\d+(?:-S\d+)?\))(?: \(proposed\))?(?: -- | → |\s*$)', w)  # ponytail: a title that itself holds "(E1-S2) -- " would end the line early
            return [i.upper() for i in re.findall(r'\((E\d+(?:-S\d+)?)\)', m.group(1))] if m else []
        listed = {i for l in txt.splitlines() if re.match(r'\d+\. |\s*- ', l) for i in wave_ids(l)}  # wave items and bullets, not reason text
        new = sum(v(op[p], 'id').upper() not in listed for p in cand)  # a plan leads the cards it lists; the rest go after it
        waves = re.findall(r'^\d+\. .*$', txt.split('## Waves', 1)[-1].split('\n## ', 1)[0], re.M)
        merged = lambda i: status.get(i, 'done') == 'done' or any(v(d, 'id').upper() == i and v(d, 'stage') in ('Live', 'Checked') for d in cards.values())
        nxt = next((w for w in waves if not all(merged(i) for i in wave_ids(w))), None)
        byid = {v(d, 'id').upper(): d for d in cards.values()}
        # a next wave that can't start (held, waiting on you, blocked) would otherwise stall the plan forever, silently
        stuck = [i for i in wave_ids(nxt or '') if i in byid and not merged(i) and (R.warn(byid[i]) or R.waiting(byid[i]) or v(byid[i], 'status') == 'blocked')]
        todo = [i for i in wave_ids(nxt or '') if not merged(i)]
        plan = (pd, len(cand) - new, new, nxt, stuck, todo, listed)
    rank = lambda p, d: (v(d, 'priority') or 'P9', -idle(p, d))
    startable = [p for p, d in op.items() if v(d, 'status') in ('backlog', 'ready') and v(d, 'id').upper() not in parents and not R.blocked(d, TREE)]
    try: gd = day((re.search(r'\d{4}-\d{2}-\d{2}', open(os.path.join(B, 'GROOM-PLAN.md'), encoding='utf-8').readline()) or [''])[0])
    except OSError: gd = None
    opn = {p: d for p, d in cards.items() if v(d, 'status') != 'done'}
    # reported to shipped: bugs git saw close, as done or shipped-tests-pass (not a card closed as not needed, expired or un-bundled)
    cyc = {pr: sorted((dn[p] - opened(p, leaf[p])).days for p in seen if p in dn and bug(leaf[p]) and h(p).get('done')
                      and v(leaf[p], 'closed_as') in ('', 'shipped-tests-pass') and (pr == '' or v(leaf[p], 'priority') == pr)) for pr in ('', 'P1', 'P2', 'P3')}
    free = [p for p, d in op.items() if not wrap(d)]
    return dict(T=T, src=src, first=first, total=sum(not wrap(d) for d in leaf.values()), open=len(free), rows=rows,
                things=sum(not R.bundle_of(d, TREE) for d in op.values()), bundles=sorted(p for p, d in op.items() if wrap(d)),
                reopened=sorted((p for p, d in op.items() if v(d, 'reopened')), key=lambda p: v(op[p], 'reopened'), reverse=True), last=lambda p: last(p, cards[p]),
                flight=flight, next_bugs=next_bugs, plan=plan, can=can,
                waiting=sorted((p for p, d in opn.items() if R.waiting(d)), key=lambda p: rank(p, opn[p])),
                held=sorted((p for p, d in opn.items() if R.warn(d) and not R.waiting(d)), key=lambda p: rank(p, opn[p])),  # waiting: listed there
                lane_idle=[p for p in flight['Now fixing'] if idle(p, op[p]) >= LANE],  # lanes work in hours: idle days = it stopped
                stalled=[p for p in flight['Other work'] if idle(p, op[p]) >= STALL],
                epics=sorted(((e, sum(v(leaf[p], 'status') == 'done' for p in kids(e)), len(kids(e))) for e in epics if kids(e)),
                             key=lambda x: (-(x[2] - x[1]), x[0])),
                cycle=cyc,
                cards=cards, idle=lambda p: idle(p, cards[p]), title=lambda p: title(cards[p]), epic_cards=epics,
                B=B, leaf=leaf, tree=TREE, startable=startable, groom_age=max(0, (T - gd).days) if gd else None, opened=lambda p: opened(p, cards[p]), done_on=dn, seen=set(seen))

def named(f, i):  # a card named from its id; an id this board doesn't hold is said so; a bundle says how many cards it does
    d = f['tree'][0].get(i.upper())
    return (R.name(d) + (f', a bundle of {len(R.parts(d))}' if R.parts(d) else '')) if d else f'a card not on this board ({i})'

def wave(f):  # the plan's next wave in plain words: its number, its mode, the cards still to do
    nxt, todo = f['plan'][3], f['plan'][5]
    mode = (re.search(r'\*\*(.+?)\*\*', nxt) or [0, 'wave'])[1]
    return f"wave {nxt.split('.')[0]} ({mode}): " + ', '.join(named(f, i) for i in todo)

def render(f, proj, needs_only=False):
    c, idle, title, T = f['cards'], f['idle'], f['title'], f['T']
    cut = R.cut
    name = lambda p, n=60: R.name(c[p], n)  # every card by its title with its id, never a bare id
    names = lambda ps, extra=lambda p: '': [f'    {name(p)}{extra(p)}' for p in ps[:TOP]] + [f'    +{len(ps) - TOP} more'] * (len(ps) > TOP)
    since = f" since {f['first']}" if f['first'] else ''
    nb, held_in = len(f['bundles']), f['open'] + len(f['bundles']) - f['things']  # a bundle is one thing to do, however many cards it does
    one = f" · {f['things']} things to do ({nb} bundle{'s hold' if nb != 1 else ' holds'} {held_in} cards)" if nb else ''
    out = [f"BOARD STATUS — {proj} · {T}",
           f"{f['total']} cards: {f['open']} open, {f['total'] - f['open']} done{one} · dates from {f['src']}{since}", '', 'IN FLIGHT']
    for k, ps in f['flight'].items():
        out.append(f"  {k:<15}{len(ps):>4}  " + (f"oldest idle {idle(ps[0])}d" if ps else '—'))
        out += names(ps)
    if nb:  # each bundle once, with every card it does by title and whether that card's own check has passed
        out += ['', 'BUNDLES']
        for p in f['bundles']:
            ms = [f['tree'][0][i] for i in R.parts(c[p]) if i in f['tree'][0]]
            out.append(f"  {name(p)} · {v(c[p], 'ground') or 'no ground given'} · {sum(v(m, 'status') != 'done' for m in ms)} of {len(ms)} parts open")
            out += [f"      {R.name(m)} -- " + ('its own check passed' if v(m, 'status') == 'done' else 'open') for m in ms]
    out += ['', 'UP NEXT']
    out.append('  Next bug       ' + ('; '.join(name(p, 60) for p in f['next_bugs']) or '—'))
    if f['plan']:
        pd, covered, new, nxt = f['plan'][:4]
        out.append(f"  PLAN.md        {pd or 'undated'} · covers {covered} of {covered + new} candidates" + (f'; {new} new since (new bugs first, the rest after its waves)' if new else ''))
        out.append(f"                 next wave: {wave(f)}" if nxt else '                 every wave is merged -- re-plan')
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
    for p in f['waiting'][:TOP]:  # BOARD.md's shape: the title, then what waits and why, then the answers
        q, under = R.ask(c[p])
        needs += [f"    {name(p, 60)} · idle {idle(p)}d", f'      {q}'] + [f'        {x}' for x in under]
    needs += [f"    +{len(f['waiting']) - TOP} more (BOARD.md lists all)"] * (len(f['waiting']) > TOP)
    p1 = [p for p in f['held'] if v(c[p], 'priority') == 'P1']  # every P1, oldest first: none may drop out of sight
    needs.append(f"  Held, high-stakes ({len(f['held'])})" + ('' if f['held'] else ': none'))
    needs += [f"    ⚠️ {name(p, 60)} · P1 · idle {idle(p)}d" for p in p1]
    needs += [f"    P2/P3 held: {len(f['held']) - len(p1)} (⚠️ on BOARD.md)"] * (len(f['held']) > len(p1))
    if needs_only: return '\n'.join(needs)
    out += [''] + needs
    drift = [(f'Now fixing, idle {LANE}d+', f['lane_idle'], '  lane stopped? it should hand the card back'),
             (f'Stalled (idle {STALL}d+)', f['stalled'], ''), (f'Shipping, idle {STALL}d+', [p for p in f['flight']['Shipping'] if idle(p) >= STALL], '  merged? run /backlog-it reconcile --prs'),
             ('Reopened', f['reopened'], '  a fix that did not hold')]
    out += ['', 'DRIFT'] + [l for k, ps, hint in drift if ps for l in [f"  {k:<22}{len(ps):>3}{hint}"] + names(ps)]
    if f['plan'] and not f['plan'][3]: out.append('  PLAN.md ran out        every wave is merged -- run /backlog-it plan')
    if f['plan'] and f['plan'][4]: out.append(f"  PLAN.md stuck          wave {f['plan'][3].split('.')[0]} waits on {', '.join(named(f, i) for i in f['plan'][4])} -- answer it or re-plan")
    if out[-1] == 'DRIFT': out.append('  none')
    out += ['', f"EPICS  (most open first)"]
    for e, dn, tot in f['epics'][:TOP]:
        ep = f['epic_cards'][e]; n = round(20 * dn / tot)
        out.append(f"  {R.name(ep, 30):<38}{'█' * n}{'░' * (20 - n)} {dn}/{tot}")
    out += [f"  +{len(f['epics']) - TOP} more epics"] * (len(f['epics']) > TOP)
    out += ['', 'CYCLE TIME  (median days, bugs, closes seen in git)']
    med = lambda xs: f'{statistics.median(xs):g} (n={len(xs)})' if xs else '—'
    out.append(f"  {'Reported → shipped':<19}{med(f['cycle'][''])} · " + ' · '.join(f"{pr} {med(f['cycle'][pr])}" for pr in ('P1', 'P2', 'P3')))
    return '\n'.join(out)

def open_prs(repo, f):
    """The repo's open pull requests from `gh`, sorted by what each needs: ([ready], [(stuck, why)], [all])
    as {n, name, card, behind}; or (None, why, []) when gh can't say. Ready says only what gh shows: no
    longer a draft, no changes asked for, every check finished and passed, no conflict with main, and not
    behind main -- worked out here by comparing its head with main, because a repo with no branch rule
    never reports "behind" (behind=None: could not tell). Whether it was reviewed is not something gh
    shows in a repo that records no review there: only the card's `reviewed:` says so. Stuck = behind or
    in conflict with main, or a draft, a failing check or a running check with no change for PR_STALL
    days. Any other open pull request is moving, and is left out."""
    if not repo: return None, 'no code folder was given', []
    def gh(*a):
        try:
            r = subprocess.run(['gh', *a], cwd=repo, capture_output=True, text=True, encoding='utf-8', timeout=60)
            return json.loads(r.stdout) if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired, ValueError): return None
    rows = gh('pr', 'list', '--state', 'open', '--limit', '100', '--json', 'number,title,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,updatedAt,baseRefName,headRefOid')
    if not isinstance(rows, list): return None, 'GitHub could not be asked', []
    card = {int(n): d for d in f['cards'].values() if v(d, 'status') != 'done' for n in re.findall(r'\d+', re.sub(r'https?://\S+', ' ', v(d, 'pr')))}
    ready, stuck, every = [], [], []
    for x in sorted(rows, key=lambda x: x['number']):
        n = x['number']; d = card.get(n)
        pr = dict(n=n, card=d, behind=0, head=x.get('headRefOid') or '', title=x.get('title') or 'no title', name=f"{R.name(d, 50)}, pull request #{n}" if d else f"\"{R.cut(x.get('title') or 'no title', 50)}\" (#{n})")
        every.append(pr)
        state = [c.get('conclusion') or c.get('state') or c.get('status') or 'PENDING' for c in x.get('statusCheckRollup') or []]
        failing = any(c in ('FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE') for c in state)
        passed = all(c in ('SUCCESS', 'SKIPPED', 'NEUTRAL') for c in state)  # ponytail: a repo with no checks at all counts as passed
        quiet = max(0, (f['T'] - (day((x.get('updatedAt') or '')[:10]) or f['T'])).days)
        merge = x.get('mergeStateStatus')
        green = not x.get('isDraft') and passed and merge not in ('DIRTY', 'BEHIND') and x.get('reviewDecision') not in ('CHANGES_REQUESTED', 'REVIEW_REQUIRED')
        if green:  # one more call, only for a pull request that would otherwise be offered for release
            cmp = gh('api', 'repos/{owner}/{repo}/compare/' + f"{x.get('baseRefName') or 'main'}...{x.get('headRefOid')}") if x.get('headRefOid') else None
            pr['behind'] = cmp.get('behind_by') if isinstance(cmp, dict) and isinstance(cmp.get('behind_by'), int) else None
        if merge == 'DIRTY': stuck.append((pr, 'it conflicts with main'))
        elif merge == 'BEHIND': stuck.append((pr, 'it is behind main'))
        elif green and pr['behind']: stuck.append((pr, f"{pr['behind']} commit{'s' * (pr['behind'] != 1)} behind main"))
        elif green: ready.append(pr)
        elif quiet >= PR_STALL: stuck.append((pr, ('a check fails, and ' if failing else '') + f'no change for {quiet} days'))
    return ready, stuck, [(pr, lambda n=pr['n']: gh('pr', 'view', str(n), '--json', 'files')) for pr in every]

def plan_files(B, ids):
    """The files PLAN.md says each of these cards will change: {id: [paths]} from each wave bullet's `files:`."""
    try: txt = open(os.path.join(B, 'PLAN.md'), encoding='utf-8').read()
    except OSError: return {}
    out, wave = {}, []
    for l in txt.splitlines():
        got = [i.upper() for i in re.findall(r'\bE\d+(?:-S\d+)?\b', l.split(' -- ')[0])]
        if re.match(r'\d+\. ', l): wave = got
        m = re.search(r'files: (.+)$', l)
        if m and re.match(r'\s+- ', l):  # a bullet under a wave: its own card, or the wave's one card
            for i in ([x for x in got if x in wave][:1] or (wave if len(wave) == 1 else [])):
                if i in ids: out[i] = [p.strip(' `') for p in m.group(1).split(',') if p.strip(' `')]
    return out

def next_thing(f, prs, lane_cap):
    """The one thing to do next: every branch of the rule that holds right now, in the rule's order, each
    as (label, sentence, [short lines under it], what picking it does, the strongest argument against it).
    The first is the recommendation; the next ones are the other choices."""
    c, T, plan = f['cards'], f['T'], f['plan']
    name = lambda p: R.name(c[p], 60)
    n_of = lambda xs, one, many: one if len(xs) == 1 else many.format(len(xs))
    top = lambda xs: xs[:3] + [f'+{len(xs) - 3} more'] * (len(xs) > 3)
    out = []
    if w := f['waiting']:
        out.append(('Answer now', f"Answer {n_of(w, 'the question that waits', 'the {} questions that wait')} on you: {n_of(w, 'that card', 'those cards')} cannot move until you do.",
                    top([name(p) for p in w]), 'I ask each one as a one-click choice', 'it takes your time now'))
    ready, stuck = (prs[0], prs[1]) if prs[0] is not None else ([], [])
    if ready:
        pr = ready[0]
        # `reviewed: <date> ready <commit>` or `<date> not ready ...`: a review counts only when it said ready AND read the
        # commit that is the pull request's head now; any other shape is no review at all
        m = re.fullmatch(r'(\d{4}-\d{2}-\d{2}) (?:(ready) ([0-9a-f]{7,40})|(not ready)\b.*)', v(pr['card'] or {}, 'reviewed'))
        current = bool(m and m.group(2) and pr['head'].startswith(m.group(3)))
        review = (f'recorded on its card for this version ({m.group(1)}).' if current else 'recorded for an earlier version, so confirm it again.' if m and m.group(2)
                  else 'its last review said not ready, so confirm it first.' if m else 'none recorded, so confirm it first.')
        facts = [pr['name'], f'Review: {review} ' + ('Could not tell whether it is up to date with main.' if pr['behind'] is None else 'Up to date with main.')]
        out.append(('Release it', f"Release {n_of(ready, '1 pull request', '{} pull requests')}: no longer a draft, no conflict with main, checks pass.",
                    facts + [f'+{len(ready) - 1} more'] * (len(ready) > 1),
                    ('I bring it up to date if needed, then release it' if current else 'I confirm its review, bring it up to date if needed, then release it'),
                    'undoing a release takes another one'))
    if stuck:
        out.append(('Sort them', f"Sort {n_of(stuck, 'the pull request that is', 'the {} pull requests that are')} stuck or out of date:",
                    top([f"{pr['name']} ({why})" for pr, why in stuck]), 'I check each one and say what it needs: an update, a fix, or closing', 'it starts no new work'))
    running, other = f['flight']['Now fixing'], f['flight']['Other work']
    free = max(0, lane_cap - len(running))
    lanes = ['No bug fix is running' if not running else f"{len(running)} bug fix{'es' * (len(running) != 1)} running, {free} of {lane_cap} lanes free"]
    if other:  # work that is not a bug fix: what moved in the last LANE days is named, the rest is only counted -- never a quiet card as the example
        moved = sorted((p for p in other if f['idle'](p) <= LANE), key=f['idle']); quiet = len(other) - len(moved)
        some = lambda k, a, b: f"{k} {a if k == 1 else b}"
        if moved:
            head = f"{lanes[0]}; {some(len(moved), 'other piece', 'other pieces')} of work moved in the last {LANE} days: "
            tail = f' +{len(moved) - 1} more' if len(moved) > 1 else ''
            lanes = [head + R.name(c[moved[0]], max(12, 103 - len(head) - len(tail) - len(v(c[moved[0]], 'id')) - 3)) + tail]
            if quiet: lanes.append(f"{some(quiet, 'more is', 'more are')} marked in progress but quiet")
        else: lanes = [f"{lanes[0]}; {some(quiet, 'piece of work is', 'pieces of work are')} marked in progress but quiet"]
    lanes = [l + '.' for l in lanes]
    status = lambda i: v(f['tree'][0].get(i, {}), 'status')
    in_force, busy, listed = False, [], set()
    if plan:
        _, _, _, nxt, held_up, todo, listed = plan
        busy = [i for i in todo if status(i) == 'in-progress']
        can = f['startable']; fresh = [p for p in can if v(c[p], 'id').upper() not in listed]
        if nxt and not held_up and free and not busy:
            lines, clash = top([named(f, i) for i in todo]) + lanes, {}
            if prs[0] is not None and prs[2]:  # does an open pull request change a file a card in this wave names?
                files = plan_files(f['B'], set(todo)); theirs = [(pr, look()) for pr, look in prs[2]]
                if not files or any(not isinstance(x, dict) for _, x in theirs): lines.append('Could not check these cards against the open pull requests: ' + ('the plan names no files.' if not files else 'their files could not be read.'))
                for i, mine in files.items():
                    for pr, x in theirs:
                        both = sorted(set(mine) & {y.get('path') for y in (x or {}).get('files', [])} if isinstance(x, dict) else ())
                        if both and i not in clash:  # short enough to keep the card, the pull request and the file all in view
                            path = both[0] if len(both[0]) <= 30 else os.path.basename(both[0])
                            who = f"pull request #{pr['n']}" if pr['card'] else f"\"{R.cut(pr['title'], 24)}\" (#{pr['n']})"
                            clash[i] = R.cut(f"{R.name(f['tree'][0][i], 28)} -- shares {path} with {who}", 106)
                lines = [clash.get(i) or named(f, i) for i in todo[:3]] + lines[min(3, len(todo)):]  # said on the card's own line
            side, k, rest = ', side by side' if len(todo) > 1 else '', nxt.split('.')[0], len(todo) - len(clash)
            whole = ('Start the wave', f"Start wave {k} of the plan: {len(todo)} card{'s' * (len(todo) != 1)}{side}.", lines,
                     'starts those cards, each in its own lane, with every gate in place', 'a new bug may need the lanes')
            if not clash: out.append(whole)
            elif rest:  # some cards share a file with an open pull request: starting the others is the recommendation
                out.append(('Start the others', f"Start {rest} of the {len(todo)} cards in wave {k} of the plan: the other{'s share' if len(clash) > 1 else ' shares'} a file with an open pull request.", lines,
                            f"starts only the {rest} card{' that shares' if rest == 1 else 's that share'} no file with an open pull request", 'the card left out waits for that pull request'))
                out.append(('Start the wave', '', [], f'starts all {len(todo)}; the shared file may then conflict', ''))
            else:
                out.append(('Wait for it', f'Wave {k} of the plan should wait: every card in it shares a file with an open pull request.', lines,
                            'nothing starts; release or finish that pull request first', 'the wave waits on someone else\'s work'))
        why, more = (('every wave in the plan is done', []) if not nxt else ('the next wave waits on a card that cannot start', [named(f, i) for i in held_up]) if held_up
                     else (f"{len(fresh)} of the {len(can)} cards that can start are not in the plan", []) if can and len(fresh) / len(can) > PLAN_STALE else ('', []))
        in_force = not why  # a plan in force keeps the order of the cards it lists
        if why:
            out.append(('Plan', f'Make a new plan: {why}.', top(more), 'works out the order the open cards run in and writes the plan; nothing starts', 'it takes an AI pass while cards wait'))
    rows = f['rows'][:GROW_WEEKS]
    grew = len(rows) == GROW_WEEKS and all(o > cl for _, o, cl, _ in rows)
    age = f['groom_age']
    if (grew and (age is None or age >= GROOM_REST)) or (age is not None and age > GROOM_AGE):
        out.append(('Groom', 'Groom the board: ' + ('more cards were opened than closed two weeks running.' if grew else f'the last groom was {age} days ago.'),
                    [f'This week {rows[0][1]} opened, {rows[0][2]} closed; the week before {rows[1][1]} opened, {rows[1][2]} closed.'] * grew,
                    're-orders the open cards and proposes which to drop; you pick what closes', 'a long run that fixes nothing by itself'))
    # with a plan in force, only a card it doesn't list may jump in (new bugs first); its own cards keep their wave
    nxt_card = [p for p in f['next_bugs'] + f['can'] if not in_force or v(c[p], 'id').upper() not in listed][:1]
    if nxt_card and free:
        d = c[nxt_card[0]]
        out.append(('Start it', f"Start the next safe card ({v(d, 'priority') or 'no priority'}{', a bug' if v(d, 'type') == 'breakfix' else ''}): nothing it waits on is open.",
                    [name(nxt_card[0])] + [f'part: {R.name(m, 60)}' for m in R.open_parts(d, f['tree'])], 'brings the card back as a prompt you can change, and runs it on your go', 'a groom or a plan might pick a better card'))
    if not out:
        why = (f"wave {plan[3].split('.')[0]} of the plan is running" if busy else f'{len(running)} of {lane_cap} lanes are busy' if running else 'no card can start safely')
        out.append(('Wait', f'Nothing to start right now: {why}, so wait.',
                    top([named(f, i) for i in busy]) + [f"{len(f['held'])} held cards wait for you at the weekly sitting."] * bool(f['held']),
                    'nothing starts; look again when a lane reports or a pull request moves', 'held cards only move when you take them up'))
    return out

def running_list(f):
    """(open lines, areas with one) on the board's running lists: every `## Running list: <area>` section
    of a card; a line is open until a `- fixed <date>: "<its first words>"` line under it quotes it."""
    n, areas = 0, set()
    for p in f['cards']:
        try: txt = open(p, encoding='utf-8-sig').read()
        except (OSError, UnicodeDecodeError): continue
        for area, body in re.findall(r'^## Running list: *(.+?) *\n(.*?)(?=^## |\Z)', txt, re.M | re.S):
            items = [l[2:].strip() for l in body.splitlines() if l.startswith('- ')]
            done = [m.group(1) for l in items if (m := re.match(r'fixed\b[^"]*"([^"]+)"', l))]
            left = [l for l in items if not l.startswith('fixed') and not any(l.startswith(q) for q in done)]
            if left: n += len(left); areas.add(area.lower())
    return n, len(areas)

def first(f, proj, prs, lane_cap, seen=False):
    """The first screen, at most about 25 lines of at most about 110 characters: DO NEXT, NEEDS YOU, what
    changed, the trend."""
    c, T, B = f['cards'], f['T'], f['B']
    name = lambda p, n=60: R.name(c[p], n)
    def fit(head, ps, tail=''):  # as many names as the line holds, then "+N more"
        line, k = head, 0
        for p in ps:
            nxt = line + (', ' if k else '') + name(p, 44)
            if len(nxt) + len(f' +{len(ps) - k - 1} more') + len(tail) > 97: break  # 110, less the line's own label
            line, k = nxt, k + 1
        return line + (f' +{len(ps) - k} more' if k < len(ps) and k else f'{len(ps)} cards' if not k and ps else '') + tail
    todo = next_thing(f, prs, lane_cap)
    lab, sent, lines, does, against = todo[0]
    out = [f'BOARD — {proj} · {T}', 'DO NEXT', f'  {sent}'] + [f'    {l}' for l in lines]
    opts = [f'{lab} -- {does} (Recommended)'] + [f'{l} -- {d}' for l, _, _, d, _ in todo[1:3 if len(lines) <= 4 else 2]] + ['Full status -- prints the whole report; nothing starts']
    out += [f'  {i}. {o}' for i, o in enumerate(opts, 1)]
    out.insert(-len(opts) + 1, f'     against: {against}')  # the strongest argument against the recommendation, right under it
    if prs[0] is None: out.append(f'  (pull requests not checked: {prs[1]})')
    out += ['', 'NEEDS YOU']
    w = f['waiting']
    for p in w[:3]:  # the title with its id, then what waits and the question: the start of the context, and always the question itself
        q = R.ask(c[p])[0]; ask = q.rsplit('. ', 1)[-1] if '. ' in q else ''
        out += [f'  {name(p)}:', '    ' + (q if len(q) <= 104 else f'{R.cut(q, 103 - len(ask))} {ask}' if 0 < len(ask) < 60 else R.cut(q, 104))]
    out += ['  Questions: nothing waits on you'] * (not w) + [f'  +{len(w) - 3} more questions (`/backlog-it status` lists them)'] * (len(w) > 3)
    if held := f['held']:
        frees = {}  # held card -> the open cards that wait on it (directly, or through a card or epic it sits under)
        for i, d in f['tree'][0].items():
            if v(d, 'status') != 'done':
                for leaf, _, via in R.needs(i, f['tree']): frees.setdefault(leaf, set()).add(i); frees.setdefault(via, set()).add(i)
        n = lambda p: len(frees.get(v(c[p], 'id').upper(), ()))
        sit = sorted(held, key=lambda p: (-n(p), v(c[p], 'priority') or 'P9', -f['idle'](p)))[:SIT[0] if w or len(lines) > 2 else SIT[1]]
        out.append(f"  Held, high-stakes: {len(held)} card{'s' * (len(held) != 1)}. For the weekly sitting, the {len(sit)} that free the most other work:")
        out += [f"    {name(p)} -- " + (f"frees {n(p)} other card{'s' * (n(p) != 1)}" if n(p) else 'nothing else waits on it') for p in sit]
    items, areas = running_list(f)
    if items: out.append(f"  Running list: {items} small item{'s' * (items != 1)} across {areas} area{'s' * (areas != 1)}")
    if ro := f['reopened']: out.append('  ' + fit(f"Reopened: {len(ro)} fix{'es' * (len(ro) != 1)} did not hold -- ", ro))  # the signal that matters
    ex = expiry(f); due = len(ex['close']) + len(ex['soon'])
    if due: out.append(f"  Quiet cards: {due} will close in the next {EXPIRE_WARN} days (`/backlog-it expire --dry-run` lists them)")
    # what changed: against the mark the last --seen look left, else the last 24 hours (dates are whole days)
    stuck_prs_now = prs[1] if prs[0] is not None else []
    stuck_now = f['lane_idle'] + f['stalled'] + [p for p in f['leaf'] if f['plan'] and v(c[p], 'id').upper() in f['plan'][4]]
    snap = dict(seen=datetime.datetime.now().isoformat(sep=' ', timespec='minutes'), ids=sorted(v(d, 'id') for d in f['leaf'].values()),
                done=sorted(v(c[p], 'id') for p in f['done_on']), stuck=sorted({v(c[p], 'id') for p in stuck_now} | {f"#{pr['n']}" for pr, _ in stuck_prs_now}))
    note = ''
    try:
        old = json.load(open(os.path.join(B, MARK), encoding='utf-8'))
        if not (isinstance(old, dict) and all(isinstance(old.get(k, []), list) for k in ('ids', 'done', 'stuck'))): raise ValueError
    except OSError: old = None
    except ValueError: old, note = None, '  (the mark of your last look could not be read, so this covers the last 24 hours)'
    if old:
        out += ['', f"SINCE YOU LAST LOOKED ({str(old.get('seen', '?'))[:16]})"]
        was = lambda k: set(old.get(k, []))
        closed = [p for p in f['done_on'] if v(c[p], 'id') not in was('done')]
        found = [p for p in f['leaf'] if v(c[p], 'id') not in was('ids')]
        stuck = [p for p in dict.fromkeys(stuck_now) if v(c[p], 'id') not in was('stuck')]
        stuck_prs = [pr['name'] for pr, _ in stuck_prs_now if f"#{pr['n']}" not in was('stuck')]
    else:
        out += ['', 'IN THE LAST 24 HOURS  (no earlier look is on record)'] + [note] * bool(note)
        since = T - D(days=1)
        closed = [p for p, on in f['done_on'].items() if on >= since and p in f['seen']]
        found = [p for p in f['leaf'] if f['opened'](p) >= since and p in f['seen']]
        stuck, stuck_prs = list(dict.fromkeys(stuck_now)), [pr['name'] for pr, _ in stuck_prs_now]
    # how a card was closed: done or shipped-tests-pass = shipped; not-needed = not needed; expired = closed by the board after EXPIRE_DAYS quiet days; any other closed_as is named as it is
    how = lambda p: {'': 'shipped', 'shipped-tests-pass': 'shipped', 'not-needed': 'not needed', 'expired': 'expired'}.get(v(c[p], 'closed_as'), f"\"{v(c[p], 'closed_as')}\"")
    def split(ps):
        shipped = [p for p in ps if how(p) == 'shipped']; rest = __import__('collections').Counter(how(p) for p in ps if how(p) != 'shipped')
        return shipped, ''.join(f' · {k} expired' if h == 'expired' else f' · {k} closed as {h}' for h, k in sorted(rest.items(), key=lambda x: (x[0] != 'not needed', x[0])))
    shipped, others = split(closed)
    line = lambda k, ps, tail='': f'  {k:<8} ' + (fit(f'{len(ps)} -- ', ps, tail) if ps else ('nothing' if not tail else '0' + tail))
    out += [line('Shipped:', shipped, others), line('Found:', found)]
    out.append(line('Stuck:', stuck) if stuck or not stuck_prs else '  Stuck:   ' + R.cut(f'{len(stuck_prs)} -- ' + ', '.join(stuck_prs), 98))
    if stuck and stuck_prs: out[-1] = R.cut(out[-1] + f" · and {len(stuck_prs)} pull request{'s' * (len(stuck_prs) != 1)}", 110)
    if f['rows']:
        _, o, cl, _ = f['rows'][0]
        wk = lambda ps: [p for p in ps if p in f['seen']]
        new = wk([p for p in f['leaf'] if T - D(days=7) < f['opened'](p) <= T]); shut = wk([p for p, on in f['done_on'].items() if T - D(days=7) < on <= T])
        bugs = lambda ps: sum(v(c[p], 'type') == 'breakfix' for p in ps)
        if o > cl:
            cat, k = max(__import__('collections').Counter(v(c[p], 'category') or 'no category' for p in new).items(), key=lambda x: x[1], default=('', 0))
            trend = f'the pile grew by {o - cl}, ' + (f'mostly new bugs ({bugs(new)} of {o})' if 2 * bugs(new) >= o else f'mostly new cards about {cat} ({k} of {o})')
        elif cl > o:
            done = split(shut)[0]; gone = sum(how(p) == 'not needed' for p in shut); old = sum(how(p) == 'expired' for p in shut)
            trend = f'the pile shrank by {cl - o}, with ' + (f'{old} quiet cards expired' if 2 * old > cl else f'{gone} cards closed as not needed' if 2 * gone > cl else f'{len(done)} fixes shipped' if 2 * bugs(done) >= len(done) else f'{len(done)} cards finished')
        else: trend = 'the pile stayed level'
        out.append(f'TREND  This week: {o} opened, {cl} closed: {trend}.')
    else: out.append('TREND  No full week of history yet.')
    if seen and not mark_seen(B, snap): out.append('  (this look was not recorded: the board folder could not be written)')
    return '\n'.join(out)

def expiry(f):
    """Which cards close by themselves, and why every other card never does: {'close': [(path, quiet days)],
    'soon': [(path, quiet days, days left)], 'later': [(path, quiet days)] not quiet long enough yet, 'kept': {path: reason}}. The written rule (the reference's `expire`):
    a card closes after EXPIRE_DAYS quiet days only when it is positively known to be one nobody asks for and that
    cannot hurt anyone. Each test below keeps a card; when a fact cannot be told, the card is kept.
    Quiet = days since the later of the card's own last change and the last change of any card that mentions it."""
    c, T, tree = f['cards'], f['T'], f['tree']
    txt, said, waited = {}, {}, set()
    for p, d in c.items():
        try: txt[p] = open(p, encoding='utf-8-sig').read()
        except (OSError, UnicodeDecodeError): txt[p] = None  # unreadable: nothing can be told, so it is kept
        for i in set(re.findall(r'\bE\d+(?:-S\d+)?\b', (txt[p] or '').upper())) - {v(d, 'id').upper()}:
            said[i] = max(said.get(i, datetime.date.min), f['last'](p))
    for i, d in tree[0].items():
        if v(d, 'status') != 'done': waited |= {leaf for leaf, _, _ in R.needs(i, tree)}
    def keeps(p, d):
        i, t = v(d, 'id').upper(), txt[p]
        sec = lambda pat: re.search(rf'^## (?:{pat})', t, re.M | re.I)
        if '/stories/' not in p or i in tree[1]: return 'an epic, or a card with cards under it'
        if t is None: return 'the card could not be read'
        if v(d, 'status') not in ('backlog', 'ready', 'designing'): return 'work on it has started (in progress, or blocked)'
        if R.warn(d): return 'high-stakes'
        if R.parts(d): return 'a bundle: it closes when its parts have'
        if R.bundle_of(d, tree): return 'part of a bundle that is still open'
        if v(d, 'pin'): return 'pinned'
        if i in waited: return 'another open card waits on it'
        if v(d, 'type') == 'breakfix': return 'a bug: a failed check, or a fault that can hurt someone'
        if v(d, 'type') not in ('story', 'task', 'spike'): return 'its type is not recorded, so it cannot be told whether it can hurt someone'
        if re.search(SAFETY, f"{v(d, 'title')} {v(d, 'category')}", re.I) or sec('High-stakes|Why high-stakes'): return 'its title or category names a safety matter (security, data, money, a gate, a failed check)'
        if sec('Captured'): return 'you reported it yourself'
        if v(d, 'reopened') or sec('Reopened'): return 'a person brought it back'
        if v(d, 'decision') or v(d, 'mode_by') == 'you' or sec('Owner|Answers'): return 'a person is named on it (a question, an answer, or an owner decision)'
        if not sec('Found'): return 'it does not say where it came from (no `## Captured`, no `## Found`), so it cannot be told that nobody asked'
        if v(d, 'pr'): return 'it has a pull request'
        return ''
    out = dict(close=[], soon=[], later=[], kept={})
    for p, d in sorted(c.items()):
        if v(d, 'status') == 'done': continue
        why = keeps(p, d)
        if why: out['kept'][p] = why; continue
        quiet = (T - max(f['last'](p), said.get(v(d, 'id').upper(), datetime.date.min))).days
        if quiet >= EXPIRE_DAYS: out['close'].append((p, quiet))
        elif quiet >= EXPIRE_DAYS - EXPIRE_WARN: out['soon'].append((p, quiet, EXPIRE_DAYS - quiet))
        else: out['later'].append((p, quiet))
    return out

def mark_seen(B, snap):
    """Record this look in <board>/.last-seen.json; False if it could not be written. It never reaches the
    board's git: when no ignore rule covers it yet, one line is added to the repo's own .git/info/exclude
    (local, never committed)."""
    git = lambda *a: subprocess.run(['git', '-C', B, *a], capture_output=True, text=True, encoding='utf-8', errors='replace')
    try:
        if git('rev-parse', '--git-dir').returncode == 0 and git('check-ignore', '-q', MARK).returncode == 1:
            ex = git('rev-parse', '--git-path', 'info/exclude').stdout.strip()
            ex = ex if os.path.isabs(ex) else os.path.join(B, ex)
            os.makedirs(os.path.dirname(ex), exist_ok=True)
            with open(ex, 'a', encoding='utf-8') as fh: fh.write(f'{MARK}\n')
        with open(os.path.join(B, MARK), 'w', encoding='utf-8') as fh: json.dump(snap, fh)
        return True
    except OSError: return False

def self_test():
    import tempfile
    T = datetime.date.today(); d = lambda n: str(T - D(days=n))
    with tempfile.TemporaryDirectory() as t:
        os.makedirs(f'{t}/items/EPIC-01-bugs/stories')
        git = lambda *a, when=None: subprocess.run(['git', '-C', t, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false',
                                                   '-c', 'core.hooksPath=/dev/null', *a], check=True, capture_output=True,
                                                  env=dict(os.environ, GIT_AUTHOR_DATE=f'{when}T12:00:00', GIT_COMMITTER_DATE=f'{when}T12:00:00'))
        def card(name, when, **kv):
            open(f'{t}/items/EPIC-01-bugs/{name}', 'w', encoding='utf-8').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
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
        card('stories/S2.md', d(9), id='E01-S2', **dict(bug, priority='P1'), stage='Live', created=d(12), signal='worker log: retry ok')
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
            card(f'stories/S{n}.md', d(30), id=f'E01-S{n}', type='story', status='blocked', priority='P1', stakes='critical', created=d(40),
                 **({'updated': str(T + D(days=1))} if n == 30 else {}))  # S30: updated: a day ahead, as a UTC stamp can be
        card('stories/S24.md', d(30), id='E01-S24', **bug, stage='Live', checkAfter='v1.41.0', created=d(40))  # an undated tag: waits forever unless flagged
        Q, A = 'The retry job gave up on 3 filings after two tries; nothing else waits on them. Retry, or refile by hand?', 'Retry -- runs them again tonight | Refile -- you re-enter the 3 by hand'
        card('stories/S3.md', d(2), id='E01-S3', title='Filings give up', **dict(bug, status='backlog'), stage='Reported', decision=Q, answers=A, created=d(2))
        card('stories/S4.md', d(2), id='E01-S4', **dict(bug, status='backlog', priority='P1'), stage='Reported', stakes='critical', created=d(2))
        card('stories/S5.md', d(1), id='E01-S5', **dict(bug, status='backlog', priority='P3'), stage='Reported', created=d(1))
        open(f'{t}/PLAN.md', 'w', encoding='utf-8').write(f'# Run Plan -- {d(5)}  (scope: all)\n\n## Waves\n1. **solo** · E01-S1 · done -- unblocks E01-S11\n2. **solo** · E01-S8 · next\n\n## Held\n- ⚠️ E01-S20 · held\n')
        git('mv', 'items/EPIC-01-bugs/stories/S1.md', 'items/EPIC-01-bugs/stories/S1-moved.md', when=d(0)); git('commit', '-qm', 'mv', when=d(0))
        card('stories/S1.md', d(0), id='E01-S15', **dict(bug, status='backlog', priority='P3'), stage='Reported', created=d(0))  # new card, S1's old path
        open(f'{t}/items/EPIC-01-bugs/stories/S19.md', 'w', encoding='utf-8').write(f'---\nid: E01-S19\ntype: breakfix\nstatus: in-progress\nstage: Cause found\ncreated: {d(5)}\nupdated: {d(0)}\n---\n')  # written, not committed: busy
        f = facts(t, T)
        ids = lambda ps: [v(f['cards'][p], 'id') for p in ps]
        rows = [r[1:] for r in f['rows']]
        # W0: opened S3 S4 S5 S7 S8 S10 S11 S15 S16 S17 S18 S19 S20 S21, closed S10 · W1: S2 / S1 (the move doesn't reset it), S12 · W2: S1 · W3: S6.
        # S9 and S14 entered git already done: neither opened nor closed here.
        assert rows == [(14, 1, 22), (1, 2, 9), (1, 0, 10), (1, 0, 9)], rows  # S30-S35, S24: open since before the window
        # no card is parked to be checked: the older Live and Checked cards sit under Shipping until their release is read
        assert set(ids(f['flight']['Shipping'])) == {'E01-S2', 'E01-S16', 'E01-S24', 'E01-S7'} and ids(f['flight']['Other work']) == ['E01-S6'] and set(f['flight']) == {'Now fixing', 'Shipping', 'Other work'}, f['flight']
        assert all(f['idle'](p) >= 0 for p in f['cards']), 'negative idle'
        r = render(f, 't')
        assert 'Live' not in r and 'Shipping, idle 14d+' in r and 'Untitled card (E01-S24)' in r.split('DRIFT')[1], r  # a merged card nobody closed is drift, not a pile
        b = R.render(t, 't')  # the report and BOARD.md agree on every status line
        for k in ('Now fixing', 'Shipping'):
            assert set(re.search(rf'\*\*{k}:\*\* (.*)', b).group(1).split(', ')) - {'—'} == {i.split('-')[-1] for i in ids(f['flight'][k])}, k
        assert ids(f['next_bugs']) == ['E01-S5'], ids(f['next_bugs'])  # S4 held, S3 waiting
        assert ids(f['can']) == ['E01-S8'] and ids(f['waiting']) == ['E01-S21', 'E01-S3'] and ids(f['held'])[-1] == 'E01-S20' and len(f['held']) == 8
        assert ids(f['lane_idle']) == ['E01-S17'] and set(ids(f['flight']['Now fixing'])) == {'E01-S17', 'E01-S18', 'E01-S19'}, f['lane_idle']  # S19: newer updated: wins
        assert ids(f['stalled']) == ['E01-S6'], f['stalled']
        # the plan leads the cards it lists (S8, held S20 behind its ⚠️); 6 it doesn't (S3 S4 S5 S15 S21, S11 only in a reason)
        assert f['plan'][1:3] == (2, 6) and f['plan'][3].startswith('2.') and 'ran out' not in render(f, 't'), f['plan']
        assert f['cycle'][''] == [10, 33] and f['cycle']['P1'] == [] and 'Reported → shipped' in r, f['cycle']  # S1 and S12: closes git saw; S9 and S14 entered done
        n = render(f, 't', needs_only=True)  # dispatch's closing list: every held P1 shown, the rest counted, nothing twice
        assert n.startswith('NEEDS YOU') and 'BURN-DOWN' not in n and '(E01-S4) · P1' in n and n.count('\n    ⚠️ ') == 7 and 'P2/P3 held: 1' in n and n.count('E01-S21') == 1, n
        assert f'    Filings give up (E01-S3) · idle 2d\n      {Q}\n        Retry -- runs them again tonight\n        Refile -- you re-enter the 3 by hand\n' in n, n
        assert '        (no context' in n.split('E01-S21')[1].split('E01-S3')[0] and 'answers not on card' in n, n  # BOARD.md's shape, gaps flagged
        assert 'growing +3.5/wk' in render(f, 't') and 'lane stopped?' in render(f, 't') and '█' in render(f, 't')
        open(f'{t}/PLAN.md', 'w', encoding='utf-8').write(f'# Run Plan -- {d(9)}\n\n## Waves\n1. **solo** · E01-S1 · done\n')  # every wave merged
        g = facts(t, T); assert g['plan'][3] is None and 'PLAN.md ran out' in render(g, 't'), g['plan']
        open(f'{t}/PLAN.md', 'w', encoding='utf-8').write(f'# Run Plan -- {d(9)}\n\n## Waves\n1. **solo** · E01-S1 · done\n2. **solo** · E01-S4 · held\n')
        g = facts(t, T)  # the next wave can't start (S4 is high-stakes): stuck, not silently waiting forever
        assert g['plan'][4] == ['E01-S4'] and 'PLAN.md stuck' in render(g, 't') and 'wave 2 waits on Untitled card (E01-S4)' in render(g, 't'), g['plan']
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
    opt = {}
    for k in ('--repo', '--lane-cap'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'status: {k} needs a value')
            opt[k] = args[i + 1]; del args[i:i + 2]
    if not opt.get('--lane-cap', '3').isdigit(): sys.exit('status: --lane-cap needs a number')
    flag = lambda k: k in args and not args.remove(k)
    needs, first_screen, seen = flag('--needs-you'), flag('--first'), flag('--seen')  # --needs-you: dispatch's closing list
    B = os.path.abspath(os.path.expanduser(args[0] if args else os.environ.get('BACKLOG_DIR', '.claude/backlog')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'status: no items/ folder in {B}')
    if not proj:
        parent = os.path.dirname(B)
        if os.path.basename(parent) == '.claude': parent = os.path.dirname(parent)
        proj = open(f'{B}/.project', encoding='utf-8').read().strip() if os.path.exists(f'{B}/.project') else os.path.basename(parent)
    if first_screen:
        f = facts(B)
        print(first(f, R.arg(proj), open_prs(os.path.expanduser(opt['--repo']) if '--repo' in opt else None, f), int(opt.get('--lane-cap', 3)), seen))
    else: print(render(facts(B), R.arg(proj), needs_only=needs))
