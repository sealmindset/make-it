#!/usr/bin/env bash
# Two rules written once in approval-block.md and carried by every lane and reviewer brief (owner, 2026-11-24).
#   - A message to the owner: a few plain lines (what happened, what it means, what to do), plain simple English,
#     names with ids, one update a day unless the owner is needed, every question one click. A style setting does
#     not reach helper agents, so the lead's own summary step says: rewrite a lane's or reviewer's report in plain
#     words, never forward its shorthand. The brief templates carry the lines so reports come back plain.
#   - A review sorts its findings: IMPORTANT (fixed before the fix ships), MINOR (at most five listed, fixed in the
#     same work if quick, the rest dropped, not filed), ALREADY THERE (a card only if it can hurt someone, else one
#     line on the skill's running list). No follow-up cards by default; a fault that repeats for three rounds goes
#     to the owner as a design choice. Capture is unchanged: the owner's own reports always become cards.
# Run where it can be run: each template is filled in as a coordinator would (every [BRACKET] replaced) and the
# brief that comes out still carries both blocks; the running list is written twice with the real card writer on a
# stand-in board and stays one section. The rest is text, pinned sentence by sentence, with controls.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 -I - "$root" "$t" <<'PY'
import os, re, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
fail = 0
def ok(name, cond, detail=''):
    global fail
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else f'\n     {str(detail)[-600:]}'))
    fail |= not cond
raw = lambda p: open(f'{root}/{p}', encoding='utf-8').read()
flat = lambda s: re.sub(r'\s+', ' ', re.sub(r'^> ?', '', s, flags=re.M))  # wrapped lines and quote marks don't matter; words do
REF = '.claude/make-it/references'
AB, PD, SDD, BB = f'{REF}/approval-block.md', f'{REF}/parallel-dispatch.md', f'{REF}/subagent-driven-development.md', f'{REF}/backlog-board.md'
TEMPLATES = ['.claude/make-it/sdd/task-reviewer-prompt.md', '.claude/make-it/sdd/adversarial-reviewer-prompt.md', '.claude/make-it/sdd/implementer-prompt.md',
             '.claude/make-it/sdd/test-writer-prompt.md', '.claude/make-it/resolve-it/investigator-prompt.md']

PLAIN = ('Report in plain simple English, in a few short lines: what happened, what it means for the owner, what they must do (often nothing). '
         'No jargon where a plain word exists. Name every card or pull request by its title with its id, never a bare id.')
SORT = ('Sort every finding (`approval-block.md`, A review sorts its findings): IMPORTANT -- the change does not do what it says; it tells the person '
        'something untrue; or it can lose data, leak a secret, or send something wrong: fixed before the fix ships. MINOR -- anything else wrong with the '
        'change: list at most five, the quickest to fix; they are fixed in the same work if quick, and the rest are dropped, not filed. ALREADY THERE -- a '
        'fault older than the change: a card only if it can lose data, leak a secret, send something wrong, or tell the person something untrue; otherwise '
        'one line for that skill\'s running list. File no follow-up cards: leftovers are fixed inside the work.')
LEAD = "rewrite it in plain words: names with ids, shortest true form; never forward a lane's shorthand"

def section(p, head):
    m = re.search(rf'^{re.escape(head)}\n(.*?)(?=^## |\Z)', raw(p), re.M | re.S)
    return flat(m.group(1)) if m else ''
# --- the two rules, written once ---
msg, rev = section(AB, '## A message to the owner'), section(AB, '## A review sorts its findings')
ok('the message rule is a section of approval-block.md', bool(msg))
for name, s in (('what happened, what it means, what to do (often nothing)', 'what happened, what it means for them, what they must do (often nothing)'),
                ('plain simple English, no jargon where a plain word exists, short sentences', 'no jargon where a plain word exists, short sentences'),
                ('names with ids, never a bare id', 'its title with its id, never a bare id or number'),
                ('one update a day unless the owner is needed', '**One update a day**, unless they are needed sooner: a decision, a blocker, or something that went wrong'),
                ('every question is one click, each answer saying what it does', '**Every question is one click**: a select, each answer saying what it does'),
                ('a style setting does not reach helper agents, so the lead rewrites', 'A style setting does not reach helper agents'),
                ('the lead\'s summary step', LEAD), ('the lines every brief carries', PLAIN)):
    ok(f'message rule: {name}', s in msg, msg[:300])
ok('the review rule is a section of approval-block.md', bool(rev))
for name, s in (('IMPORTANT, and when it is fixed', '**IMPORTANT** -- the change does not do what it says; it tells the person something untrue; or it can lose data, leak a secret, or send something wrong. Fixed before the fix ships.'),
                ('MINOR: at most five, the rest dropped, not filed', '**MINOR** -- anything else wrong with the change. At most five are listed, the quickest to fix; they are fixed in the same work if quick. The rest are dropped, not filed.'),
                ('ALREADY THERE: a card only if it can hurt someone, else the running list', '**ALREADY THERE** -- a fault older than the change. It becomes a card only if it can lose data, leak a secret, send something wrong, or tell the person something untrue; otherwise it is one line on that skill\'s running list'),
                ('where the running list lives is named', '(`backlog-board.md`, The running list)'),
                ('no follow-up cards by default', 'a lane or a reviewer files none, and leftovers are fixed inside the work'),
                ('three rounds -> the owner, one click, not a fourth patch', 'A fault that comes back for three review rounds goes to the owner as a design choice, one click, not a fourth patch.'),
                ('capture is unchanged', 'What the owner reports is different: `/backlog-it capture` and `bug` always become cards.'),
                ('older severity words are mapped', 'Critical and Important are both IMPORTANT'), ('the lines every brief carries', SORT)):
    ok(f'review rule: {name}', s in rev, rev[:300])
ok('each rule is written once: its heading appears once in the shipped files',
   all(sum(raw(os.path.relpath(os.path.join(dp, f), root)).count(h) for dp, _, fs in os.walk(f'{root}/.claude') for f in fs if f.endswith('.md')) == 1
       for h in ('## A message to the owner', '## A review sorts its findings')))

# --- every brief template carries both blocks, and so does a brief built from it ---
def build(p):  # fill the template as a coordinator does: drop the leading comment, replace every [BRACKET]
    s = re.sub(r'\A<!--.*?-->\s*', '', raw(p), flags=re.S)
    return re.sub(r'\[[A-Z][A-Z_]+[^\]]*\]', 'filled-in', s)
for p in TEMPLATES:
    b, n = flat(build(p)), os.path.basename(p)
    ok(f'{n}: a brief built from it tells the agent to report plainly', PLAIN in b, n)
    ok(f'{n}: a brief built from it carries the sorting rule', SORT in b, n)
    ok(f'{n}: the built brief has no placeholder left', not re.search(r'\[[A-Z][A-Z_]{3,}', b), re.findall(r'\[[A-Z][A-Z_]{3,}[^\]]*', b)[:3])
prompt = flat(re.search(r'^## Agent prompt structure\n(.*?)^## ', raw(PD), re.M | re.S).group(1))
ok('parallel-dispatch.md: the lane prompt example carries both blocks', PLAIN in prompt and SORT in prompt, prompt[-400:])
ok('parallel-dispatch.md: every agent prompt carries them, said as a rule', 'Every agent prompt also carries the two blocks from `approval-block.md`' in prompt)
ok('(control) a brief whose block lost a sentence fails', SORT not in flat(build(TEMPLATES[0])).replace('and the rest are dropped, not filed', 'and the rest are filed'))

# --- the lead's own summary step says: rewrite, never forward ---
for p in (PD, SDD, '.claude/commands/dispatch-it.md', '.claude/commands/subagent-it.md', '.claude/commands/resolve-it.md', '.claude/commands/backlog-it.md'):
    f = flat(raw(p))
    ok(f'{os.path.basename(p)}: the lead rewrites a report in plain words and never forwards shorthand', LEAD in f)
    ok(f'{os.path.basename(p)}: points at both rules', 'A message to the owner' in f and 'A review sorts its findings' in f)

# --- lanes and reviewers stop making follow-up cards by default ---
task, adv, inv = flat(raw(TEMPLATES[0])), flat(raw(TEMPLATES[1])), flat(raw(TEMPLATES[4]))
rz, rzc, sdd = flat(raw(f'{REF}/resolve-it.md')), flat(raw('.claude/commands/resolve-it.md')), flat(raw(SDD))
ok('the task reviewer lists at most five minors and an already-there line', '[Minor] ... (at most five, the quickest to fix)' in task and '[Already there] ...' in task and 'do not self-censor' not in task)
ok('the adversarial reviewer does the same', 'at most five Minor, the quickest to fix' in adv and '[Already there]' in adv)
ok('the investigator no longer collects for follow-up cards', 'for follow-up cards' not in inv and 'sorted as ALREADY THERE' in inv)
ok('/resolve-it no longer files follow-ups for anything deferred', 'File follow-ups for anything deferred' not in rz and 'every deferred item' not in rzc
   and 'Nothing else is deferred to a card' in rz and 'follow-up cards for deferred items' not in rz)
ok('/resolve-it still files a card for a manual unblock (the system should have done it)', 'a manual unblock from the run gets its card' in rz)
ok('subagent-driven-development.md: minors are capped and fixed in the work, not rolled up', 'at most five **Minor** findings, the quickest to fix' in sdd
   and 'record **Minor** findings in the ledger and point the final review at that list' not in sdd)
ok('subagent-driven-development.md: three rounds on one root cause is still the owner\'s design choice', 'Same root cause three rounds running' in sdd)
bb, cmd = flat(raw(BB)), flat(raw('.claude/commands/backlog-it.md'))
ok('backlog-board.md: the running list has one home and a way to clear it', '### The running list' in raw(BB) and 'the `## Running list` section of the epic card the work\'s card sits under' in bb
   and 'card.py append <epic id> "Running list"' in bb and 'A line is open until a `fixed` line quotes it' in bb)
ok('capture is unchanged: card first, and the owner\'s own reports always become cards', 'the card before any question' in cmd and "the owner's own reports always become cards" in cmd)

# --- run: the running list, written twice with the real card writer, is one section ---
B = f'{tmp}/s/board'
subprocess.run([sys.executable, f'{root}/scripts/backlog-stand-in/make-board.py', f'{tmp}/s'], check=True)
card = lambda text: subprocess.run([sys.executable, f'{root}/.claude/make-it/backlog/bin/card.py', '--board', B, '--no-sync', 'append', 'E01', 'Running list'],
                                   input=text, capture_output=True, text=True, encoding='utf-8')
r1 = card('- export: the header row is counted as data (export.py) · found 2026-11-24 in "Export drops the last row (E01-S10)"\n')
r2 = card('- fixed 2026-11-25: "export: the header row is counted" · pull request 15\n')
epic = open(f'{B}/items/EPIC-01-bugs/epic.md', encoding='utf-8').read()
ok('the running list is one section on the epic card, and a fixed line lands under it', r1.returncode == 0 and r2.returncode == 0 and epic.count('## Running list') == 1
   and re.search(r'## Running list\n- export: the header row.*\n- fixed 2026-11-25: "export: the header row is counted"', epic) is not None, epic + r1.stderr + r2.stderr)
sys.exit(fail)
PY
