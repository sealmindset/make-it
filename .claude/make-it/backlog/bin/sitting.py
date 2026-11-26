#!/usr/bin/env python3
"""The weekly sitting: the few held high-stakes cards that free the most other work, brought to the owner
one question at a time. No AI call here -- the pick, whether a sitting is due, and the record are facts and a
written rule; the asking is the skill's (`/backlog-it sitting`).

Usage: sitting.py [--board PATH] [--project NAME] pick [--as-of YYYY-MM-DD]   (read-only)
       sitting.py [--board PATH] [--project NAME] due [--as-of YYYY-MM-DD]    (read-only, one line)
       sitting.py [--board PATH] [--project NAME] [--no-sync] answer <id> <answer name>   (stdin: what that answer does)
       sitting.py [--board PATH] [--project NAME] [--no-sync] not-now <id>
  --board defaults to the board this folder uses (regen-board.py find_board, the one rule).

pick     the cards for this sitting, by the written rule in status.py (`sitting`): held high-stakes cards with
         no question already waiting; the one that frees the most other cards first, then the higher priority,
         then the older card; a bundle counts once; at most SIT[1]. A card answered at a sitting, or put off as
         "not now" in the last SIT_REST days, is left out for as long as it has not changed since.
due      whether a sitting is due: a card can be brought, and no sitting is on record in the last SIT_EVERY days.
answer   writes the owner's pick on the card under `## Answers` (and clears `decision:` and `answers:`), then
         marks it `sat: <date> answered <print of the card>` so it is not brought again unless it changes.
not-now  keeps the "not now" on the card the same way (`sat: <date> not-now <print>`): not brought again for
         SIT_REST days unless the card changes.
--as-of works the answer out for another day, and is for `pick` and `due` only: a record always carries today.
Writes go through card.py's lock, pull and sync: the line printed ends with what happened, and exit 3 means
saved here but not sent (do not run it again). Any other non-zero exit = nothing written.
"""
import datetime, importlib.util, os, re, sys

_bin = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
def _load(name, f):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_bin, f))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
C, S = _load('card', 'card.py'), _load('status_board', 'status.py')
R, v = C.R, C.R.v

def no(msg): sys.exit(f'sitting: nothing written -- {msg}')

def pick(B, proj, T=None):
    f = S.facts(B, T); s = S.sitting(f); c, T = f['cards'], f['T']
    n = len(f['held'])
    out = [f"WEEKLY SITTING — {proj} · {T} · {n} held high-stakes card{'s' * (n != 1)}, {len(s['picks'])} brought to this sitting",
           f"The rule: the card that frees the most other cards first, then the higher priority, then the older card; a bundle counts once; at most {S.SIT[1]}.",
           S.due_line(s, T)]
    for k, (p, waits) in enumerate(s['picks'], 1):
        d = c[p]; txt = open(p, encoding='utf-8-sig').read()
        why = re.search(r'^## (?:Why high-stakes|High-stakes)[^\n]*\n+([^\n#][^\n]*)', txt, re.M | re.I)
        out += [f"{k}. {R.name(d, 80)} · {v(d, 'priority') or 'no priority'} · open {max(0, (T - f['opened'](p)).days)} days",
                '   frees ' + (f"{len(waits)} other card{'s' * (len(waits) != 1)}: " + ', '.join(S.named(f, i) for i in waits[:3]) + (f' +{len(waits) - 3} more' if len(waits) > 3 else '') if waits else 'no other card: nothing else waits on it'),
                '   why it is held: ' + (R.cut(why.group(1).strip(), 150) if why else 'it is marked high-stakes (`stakes: critical`); the card says what it touches'),
                f'   the card: {p}']
    left = [f"{len(s['answered'])} already answered at a sitting"] * bool(s['answered']) + ([f"{len(s['rested'])} put off as \"not now\" (back from {min(u for _, u in s['rested'])})"] if s['rested'] else [])
    if left: out.append('Left out: ' + ' · '.join(left) + ' -- each comes back sooner if its card changes')
    rest = n - len(s['picks']) - len(s['answered']) - len(s['rested'])
    if rest > 0: out.append(f"{rest} more held card{'s wait' if rest != 1 else ' waits'} for a later sitting (`/backlog-it status` counts them).")
    return '\n'.join(out)

def record(B, cid, label, text, proj, nosync, T=None):
    """Write the owner's answer (or "not now", label None) on a held card and mark it as sat."""
    T = T or datetime.date.today()
    p = C.find(B, cid); raw, d = R.fm(p), R.load(B)[p]  # d: the card as the board reads it -- a bundle is high-stakes when a part is
    if v(d, 'status') == 'done': no(f'{R.name(d)} is closed')
    if not R.warn(d): no(f'{R.name(d)} is not a held high-stakes card: the sitting is for those; answer any other question with `card.py append {v(d, "id")} Answers`')
    if label is None:
        kind, line = 'not-now', f'- {T} weekly sitting -- **Not now**: stays on the board; not brought again before {T + datetime.timedelta(days=S.SIT_REST)} unless the card changes'
    else:
        kind, line = 'answered', f"- {T} weekly sitting -- **{label}**: {' '.join(text.split())}"
    C.write(p, {k: None for k in ('decision', 'answers') if k in raw}, 'Answers', line, T)
    C.write(p, {'sat': f"{T} {kind} {S.stamp_of(open(p, encoding='utf-8-sig').read())}"}, T=T)  # the print of the card as answered: any later change brings it back
    said = 'kept as "not now"' if label is None else f'answer recorded at the weekly sitting ("{label}")'
    if nosync: sent, rc = 'written here, NOT sent to the shared board: --no-sync leaves the commit and the push to you', 0
    else:
        try: sent, rc = C.sync(B, [p], f'card: {v(d, "id")}: weekly sitting, {kind}'[:72], proj), 0
        except C.NotSent as e: sent, rc = f'{e} -- saved here; do NOT run this again; it is sent with the next card write', 3
    print(f'{R.name(d)}: {said} · {sent}')
    return rc

def main(args):
    opts = {}
    for k in ('--board', '--project', '--as-of'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'sitting: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    nosync = '--no-sync' in args; args = [a for a in args if a != '--no-sync']
    B = os.path.abspath(os.path.expanduser(opts.get('--board') or R.default_board('sitting')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'sitting: no items/ folder in {B}')
    proj = opts.get('--project')
    home = os.path.dirname(B); home = os.path.dirname(home) if os.path.basename(home) == '.claude' else home
    said = R.arg(proj or (open(f'{B}/.project', encoding='utf-8').read().strip() if os.path.exists(f'{B}/.project') else os.path.basename(home)))
    verb, rest = (args[0], [R.arg(a) for a in args[1:]]) if args else ('', [])
    asof = S.day(opts['--as-of']) if '--as-of' in opts else None
    if '--as-of' in opts and (not asof or verb not in ('pick', 'due')): no('--as-of takes a date (YYYY-MM-DD) and is for `pick` and `due` only')
    if verb == 'pick' and not rest: return print(pick(B, said, asof))
    if verb == 'due' and not rest:
        f = S.facts(B, asof); return print(S.due_line(S.sitting(f), f['T']))
    if verb == 'answer' and len(rest) == 2 and rest[1].strip():
        if sys.stdin.isatty(): sys.exit('sitting: pipe what the answer does on stdin')
        t = sys.stdin.read()
        if not t.strip(): no('empty text on stdin: say what the answer does')
        label = None if rest[1].strip().lower() in ('not now', 'not-now') else rest[1].strip()
        C.lock(B); C.pull(B, proj); sys.exit(record(B, rest[0], label, t, proj, nosync))
    if verb == 'not-now' and len(rest) == 1: C.lock(B); C.pull(B, proj); sys.exit(record(B, rest[0], None, '', proj, nosync))
    sys.exit(__doc__)

if __name__ == '__main__':
    main(sys.argv[1:])
