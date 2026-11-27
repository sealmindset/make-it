# The Approval Block (how a skill asks, and what an agent discloses)

The working form of "Keep the human able to notice" (`human-in-the-loop.md`, rules 1, 2, 3 and
5) for every skill with an approval point and every agent a skill dispatches. A skill links this
file from its `<execution_context>`; agent prompts carry the disclosure line themselves. It also
holds the two rules every brief carries: how a message to the owner reads, and how a review sorts
what it finds.

## Pick the tier before you ask

| Tier | What it is | How |
|------|-----------|-----|
| **Routine** | Reversible, expected, inside the task's scope | Don't ask. Do it, say so in one line, and list it in the end-of-run summary. |
| **Consequential** | Changes what ships, costs real time or money, or is awkward to undo | One ask: batch every such question of this step together. |
| **High-stakes** | Destructive or hard to undo; auth, permissions, secrets; schema or migrations; live data; money; anything sent outside the team; breaking changes | **Active confirmation:** the human picks the specific -- the count, the target, the case -- never a plain yes. This gate is never batched away or removed. |

Never ask a question whose answer wouldn't change what happens. Torn between two tiers → the
higher one.

## Every ask is decision-ready

1. **What changes** -- the action, in plain words.
2. **The evidence** -- what you looked at and what it showed (file, log, test, screen), not what
   you assume.
3. **Blast radius and undo** -- what it touches, and how to take it back (or "no undo").
4. **What is unusual** -- how this differs from the routine version of the step ("nothing" is a
   fine answer).
5. **The one thing to check** -- the single fact to look at before deciding.

No bare "approve? (y/n)" or "OK to proceed?". An option marked **Recommended** carries its
strongest counter-argument beside it. For a high-stakes ask, the options are the specifics (which
rows, which environment), one option each.

## Every ask is a select, and a "no" is kept

- **A select, never typing.** Ask with AskUserQuestion where there is one; otherwise give the
  options by name. Never ask the user to type a path, a name, a count or a set phrase to confirm
  something. For a high-stakes ask the options are still the specifics: one option per target
  (a multi-select when there are several), so a pick names exactly what happens. Free text is
  only for information you can't know, such as a reason in the user's own words.
- **A "no" or "not now" is kept.** In a project with a `.make-it-state.md`, write it under
  `## Put off by your choice` (one line: what was offered, and the date -- /resume-it defines the
  section) and don't raise it again unless the user asks or what it covers has changed. A skill
  that rewrites that file keeps the section. In a project without that file nothing is kept, and
  the next run may ask again.
- **Only an offer is put off.** A stop, a failed check, a security finding or a gate is never put
  off: the check still runs, still reports, and still holds what it held. An ask that a step needs
  in order to go on (a blocked download, a port in use) is asked again whenever that step is
  blocked again, whatever was answered last time.
- **A yes to an action is never kept.** A send, a deploy, a delete, a migration, a payment or a
  paused security tool is asked each time it comes up. Keeping a "no" approves nothing.
- **The same stop twice is make-it's fault, and is said so.** When a stop or an ask comes up
  again with nothing changed since the user last answered it, don't present it as new. Say one
  line -- "I'm stopped on the same thing as last time, and I shouldn't be asking you twice: that
  is a fault in make-it." -- give the way out (the earlier answer, or what would change it), and
  note it in the run's report so it gets fixed. It stays stopped: a repeat never turns a stop
  into a go, and this never applies to approving an action, which is asked every time.
- **No "all of them" option.** When the ask lists several targets, each is its own pick. If an
  answer picks both an action and "not sure" or "stop", it is a stop.

## A list of asks ("Waiting on you")

When a reply, a run summary, or a lane's closing message lists what waits on the human, each item
is the short form of an ask: a few lines someone with no prior context can answer. It carries what
it is, what waits and why, and the answers; the full five-point ask above comes when the human
takes the item up.
- **What it is**, in plain words: the card's or PR's title, never a bare id or number; an internal
  term ("apply-day", "fold") only with a gloss.
- **What waits, and why** -- one or two plain sentences, then the question.
- **The answers** -- 2-4, each named with what happens if picked (`Go -- deploys today`); a
  Recommended one carries its strongest counter-argument.
- **A batch is one item**: one line per group saying what it is and what to do with it ("5
  dependency upgrades that only touch CI -- take them through one at a time?"), never a list of numbers.
  A high-stakes item is never batched: it stays its own item, and its answers are the specifics.

An item you can't explain in two plain sentences isn't ready to ask. On a backlog board the item
is the card's `decision:` and `answers:` (`backlog-board.md`, Waiting on you).

## A message to the owner

The owner is the person the work is for. Whatever a skill, a lead, a lane or a reviewer writes for
them to read -- an update, a summary, a closing report, a question -- follows one rule:

- **A few plain lines**: what happened, what it means for them, what they must do (often nothing).
- **Plain simple English**: no jargon where a plain word exists, short sentences, no shorthand of
  your own.
- **Names with ids**: a card or a pull request is its title with its id, never a bare id or number.
- **One update a day**, unless they are needed sooner: a decision, a blocker, or something that
  went wrong.
- **Every question is one click**: a select, each answer saying what it does (Every ask is a
  select, above).

**The lead rewrites.** A style setting does not reach helper agents, so the rule sits in the lead's
own summary step: when you pass on a lane's or a reviewer's report, rewrite it in plain words: names with ids, shortest true form; never forward a lane's shorthand.

**Every brief carries it.** Each lane and reviewer brief template holds these lines, so a report
comes back plain in the first place:

> Report in plain simple English, in a few short lines: what happened, what it means for the owner, what
> they must do (often nothing). No jargon where a plain word exists. Name every card or pull request by its
> title with its id, never a bare id.

## A review sorts its findings

Every review -- a task review, an adversarial review, a lane's check of its own work, the lead's
check before it integrates -- sorts each finding into one of three, and says which:

- **IMPORTANT** -- the change does not do what it says; it tells the person something untrue; or it
  can lose data, leak a secret, or send something wrong. Fixed before the fix ships.
- **MINOR** -- anything else wrong with the change. At most five are listed, the quickest to fix;
  they are fixed in the same work if quick. The rest are dropped, not filed.
- **ALREADY THERE** -- a fault older than the change. It becomes a card only if it can lose data,
  leak a secret, send something wrong, or tell the person something untrue; otherwise it is one line
  on that skill's running list (`backlog-board.md`, The running list), which a later lane working in
  the same place clears.

**No follow-up cards by default**: a lane or a reviewer files none, and leftovers are fixed inside
the work. A fault that comes back for three review rounds goes to the owner as a design choice, one
click, not a fourth patch. What the owner reports is different: `/backlog-it capture` and `bug`
always become cards.

Where a template grades findings Critical / Important / Minor, Critical and Important are both
IMPORTANT here, and the cap of five is on its Minor findings.

**Every brief carries it.** Each reviewer and lane brief template holds these lines:

> Sort every finding (`approval-block.md`, A review sorts its findings): IMPORTANT -- the change does
> not do what it says; it tells the person something untrue; or it can lose data, leak a secret, or send
> something wrong: fixed before the fix ships. MINOR -- anything else wrong with the change: list at most
> five, the quickest to fix; they are fixed in the same work if quick, and the rest are dropped, not
> filed. ALREADY THERE -- a fault older than the change: a card only if it can lose data, leak a secret,
> send something wrong, or tell the person something untrue; otherwise one line for that skill's running
> list. File no follow-up cards: leftovers are fixed inside the work.

## Leave nothing running

A background command a helper starts (a CI watch, a long test run) keeps running after the helper
gives its report. In a session someone works in there is no time limit on it, so a finished helper
can hold one for days.

**Every brief carries it.** Each lane and reviewer brief template holds these lines:

> Wait for CI or long tests with a foreground command that has a time limit, not a background one.
> Never give your final report while a background command you started is still running: stop each one
> with TaskStop first.

**The lead stops each helper.** When a helper's final report arrives, stop it (TaskStop) so nothing it
started is left running.

**A hook backs it up.** The installers register `~/.claude/make-it/hooks/no-leftover-commands.py` as a
`SubagentStop` hook. When a helper tries to finish, it reads that helper's own transcript; if a
background command the helper started is still running, it sends the helper back once with "You still
have a background command running: <ids>. Stop each with TaskStop, then give your report." The second
time, or when it can't read the transcript, it lets the helper finish: a tripwire, never a trap.

## Agents disclose every safeguard they bypassed or weakened

Every agent that changes files -- a test-writer, implementer, fixer, or dispatch lane -- ends its
report with one line: `SAFEGUARDS: none` -- or each one, with what, where, and why. It counts:
- `--no-verify`, or any hook or check skipped;
- a test skipped, disabled, deleted, or loosened (a weaker assertion, a wider tolerance, a
  changed expected value) -- tests outside the task included;
- an edited hook, linter rule, CI step, evaluator, threshold, or coverage floor;
- wider permissions or token scopes for an agent, a tool, or CI.

**Not a weakening:** a change the brief (or the dispatch prompt) explicitly asks for -- an
expected value it states, the tests of a function it removes, the app's own roles, permissions,
or limits it specifies. Reviewers check it against the brief's words.

Mentioning a weakening elsewhere in the report ("tidied a test") doesn't count; it goes on the
line. Disclosed is not approved: each one is undone, or the human decides, and one the human
accepts is logged and never asked about again. **Undisclosed is a Critical finding**, and it is
undone. Reviewers -- the SDD task reviewer, the adversarial reviewer, and dispatch-it's
integration step -- check every weakening in the diff against every SAFEGUARDS line the task
produced.
