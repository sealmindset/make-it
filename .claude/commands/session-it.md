---
name: session-it
description: Per-session checkpoint for folders where you run more than one Claude session at once. Same six-section handoff as /clear-it, but written to a lane owned by THIS session (.handoffs/handoff-<id>.md) so parallel sessions in the same directory never overwrite or contaminate each other. Use /session-it to checkpoint, /session-it list to see lanes, /session-it resume to adopt a lane after /clear.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
---

<objective>

/session-it is /clear-it for people who run several Claude sessions in the same folder.

/clear-it writes a single `handoff.md` at the project root. That is correct for one session
and actively harmful for two: the second session's checkpoint silently overwrites the
first's, and a resuming session reads a handoff describing work it never did. Two threads
of reasoning get spliced into one file and the reader cannot tell which sentence belongs to
which effort.

/session-it fixes that by giving each session its own **lane**:

```
.handoffs/
  handoff-c4d2e427.md      <- lane owned by session c4d2e427-...
  history-c4d2e427.md      <- that lane's archive
  handoff-c8379bec.md      <- a different session, same folder, untouched
  history-c8379bec.md
```

The lane content is the **same six sections as /clear-it**, deliberately -- Goal, Current
State, Active Files, Changes Made, Failed Approaches, Next Steps -- so the two skills stay
interchangeable in the reader's head. What differs is the addressing, and the strict rule
that a session reads and writes ONLY its own lane.

/session-it is fully independent of /clear-it. It never reads, writes, or archives
`handoff.md` or `.handoff-history.md`. Both skills can be used in the same repository.

Like /clear-it, this is a LIGHTWEIGHT checkpoint. It does not stop containers, update
CHANGELOG.md/TODO.md, or commit code (that is /wrap-it). It works in ANY project.

</objective>

<critical_insight>

**Two failure modes, not one.**

/clear-it exists to fight context rot: the knowledge of which hypotheses were tried and
disproven lives only in the live conversation, and section 5 (Failed Approaches) is the
whole point of writing anything down.

/session-it inherits that and adds a second failure mode: **cross-session contamination.**
A dead end that was fatal in session A may be the correct approach in session B, because B
is working on a different problem in the same tree. A handoff that mixes them is worse than
no handoff, because the next session will trust it and rule out something that was never
ruled out.

So the anti-contamination rules below are not housekeeping -- they are the reason this skill
exists, on equal footing with Failed Approaches:

- Write only to your own lane.
- Do NOT read another lane's body into context. When listing lanes, read the Goal line and
  the timestamp only.
- Never merge lanes. If two lanes turn out to be the same effort, say so and let the user
  decide; do not fold one into the other.

</critical_insight>

<process>

<step name="mode">

**Determine the mode from `$ARGUMENTS`:**

| Arguments | Mode | What it does |
|---|---|---|
| *(empty)* | **checkpoint** | Write this session's lane. The default. |
| `list` | **list** | Show every lane in this folder, metadata only. |
| `resume` | **resume** | Show lanes, let the user pick one, adopt it as this session's lane. |
| `resume <key>` | **resume** | Adopt lane `<key>` directly, no prompt. |

Anything else: treat as checkpoint and mention that the argument was ignored.

</step>

<step name="identify">

**Establish which session this is. Run this before anything else, in every mode.**

There is no `CLAUDE_SESSION_ID` environment variable. Session identity is recovered by
planting a unique token in this conversation and finding which transcript file contains it.
This is exact and works with any number of concurrent sessions.

**Call 1 -- plant the token.** Invent a fresh random token yourself (do NOT generate it at
runtime; it must appear literally in the command text so it lands in this session's
transcript). Use the form `SESSIONIT-PROBE-` followed by 12 random hex characters:

```bash
echo "SESSIONIT-PROBE-a91f3c07d2b4 planted"
```

**Call 2 -- find the transcript that contains it.** This must be a SEPARATE Bash call, so
that call 1 has been flushed to the transcript on disk before the search runs:

```bash
SLUG=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
DIR="$HOME/.claude/projects/$SLUG"
[ -d "$DIR" ] || DIR=$(dirname "$(grep -rl 'SESSIONIT-PROBE-a91f3c07d2b4' "$HOME/.claude/projects"/*/*.jsonl 2>/dev/null | head -1)")
HIT=$(grep -l 'SESSIONIT-PROBE-a91f3c07d2b4' "$DIR"/*.jsonl 2>/dev/null | xargs -r ls -t 2>/dev/null | head -1)
echo "transcript=$HIT"
echo "uuid=$(basename "${HIT:-unknown}" .jsonl)"
```

Substitute your own token for `a91f3c07d2b4` in both calls -- the same value in each.

**Fallbacks, in order:**
1. Token found in exactly one transcript -- use it. This is the normal path.
2. Token found in more than one -- use the most recently modified (already handled by
   `ls -t` above).
3. Token found in none (transcript not yet flushed, or an unusual install layout) -- fall
   back to the most recently modified `*.jsonl` in `$DIR`, and say plainly in your final
   output that the session id was inferred by modification time rather than confirmed.
4. No transcript directory at all -- tell the user, and ask whether to write a single
   `.handoffs/handoff-manual.md` instead. Do not silently write to a guessed lane.

**Derive the lane key:** the first 8 characters of the session UUID. If `.handoffs/` already
holds a lane with that 8-character prefix belonging to a *different* full UUID, use 12
characters instead.

**Then find this session's existing lane, if any:**

```bash
grep -l '<full-session-uuid>' .handoffs/handoff-*.md 2>/dev/null
```

A session's UUID appears in the `Session chain` of the lane it owns, including lanes adopted
via `resume`. If a lane lists this UUID, that lane is this session's lane regardless of its
filename -- update it, do not create a second one. This is what makes a lane survive `/clear`
and `/resume-it`, which start a new session UUID.

</step>

<step name="list">

**Mode `list`, and the first half of mode `resume`.**

Read from each `.handoffs/handoff-*.md`: **the filename, the Goal line, the Written
timestamp, the branch, and whether it is this session's lane.** Nothing else. Do not read
lane bodies.

```
Lanes in .handoffs/ (3)

  * handoff-c4d2e427.md   THIS SESSION   saved 10:32   branch feat/pi-drop-box-altsleep-poc
      Goal: Assess com.sleepnum.alt for Sleep Number IP misappropriation

    handoff-c8379bec.md                  saved 10:25   branch feat/voice-fallback
      Goal: Get the model fallback leg working through Foundry

    handoff-1db7529c.md                  saved Aug 12  branch main
      Goal: Pi drop-box provisioning script
```

Mark stale lanes (not written in 14+ days) as `stale`. Do not delete anything.

In `list` mode, stop here.

</step>

<step name="adopt">

**Mode `resume` only.**

After a `/clear`, this session has a NEW uuid and therefore no lane. Adopting one binds it.

1. Show the lane list (previous step).
2. If a key was given as an argument, use it. Otherwise ask the user which lane to adopt,
   with AskUserQuestion, one option per lane labelled with its Goal line.
3. Read the chosen lane IN FULL. This is the one and only time you read a lane you do not
   already own.
4. Append this session's UUID to that lane's `Session chain` line, and update `Written`.
5. Confirm briefly, then continue the user's work from the lane's Next Steps.

Never adopt a lane that already lists a *different* live session as its most recent chain
entry unless the user explicitly confirms -- that is two sessions sharing one lane, which
reintroduces exactly the problem this skill prevents. Warn, then honour their decision.

</step>

<step name="gather">

**Mode `checkpoint`. Gather silently -- do not interrogate the user unless the session
context is genuinely empty.**

**1. From the current conversation (primary source):**
- The original goal and any scope changes since
- What was attempted, what worked, what failed and why
- Assumptions that were made and later disproven
- The step that was in progress when /session-it was invoked

**2. From disk (verification and gap-filling):**

```bash
git status --short 2>/dev/null
git log --oneline -15 2>/dev/null
git diff --stat 2>/dev/null
git branch --show-current 2>/dev/null
git rev-parse --show-toplevel 2>/dev/null
```

If this session is running in a git worktree, record the worktree path -- two sessions in
sibling worktrees of the same repo are a common reason to be using this skill.

**3. Make-it context, if present (read silently):**
- `.make-it-state.md`, `.make-it/app-context.json`, `TODO.md` -- fold anything relevant into
  the six sections. If absent, this is not a make-it project; proceed anyway.

**4. If context is thin** (e.g. /session-it invoked at the very start of a session), ask the
user ONE question: "What should this lane say you were working toward and what's next?" Do
not fabricate content for sections you have no evidence for -- write "None this session".

**Do not** consult other lanes to fill gaps. An empty section in your lane is correct; a
section borrowed from another session's lane is a defect.

</step>

<step name="prepare">

**Create the directory and keep it out of commits.**

```bash
mkdir -p .handoffs
```

If a `.gitignore` exists at the repo root and does not already ignore `.handoffs/`, append:

```
# /session-it per-session handoff lanes
.handoffs/
```

If there is no `.gitignore`, create one containing exactly that. If `.handoffs/` is already
tracked in git, do not attempt to untrack it -- say so in the final output and leave it to
the user.

</step>

<step name="archive">

**Preserve this lane's previous content before overwriting -- within the lane only.**

If `.handoffs/handoff-<key>.md` exists, prepend its full content to
`.handoffs/history-<key>.md` under a dated heading, newest first:

```markdown
## Archived <YYYY-MM-DD HH:MM>

<previous lane content>
```

Failed-approach knowledge must never be silently lost: if the old lane's **Failed
Approaches** section lists dead ends still relevant to the current goal, CARRY THEM FORWARD
into the new lane file (marked `(carried forward)`), not just into the archive.

Never write to another lane's history file.

</step>

<step name="write">

**Write `.handoffs/handoff-<key>.md`:**

```markdown
# Session handoff -- <project name> -- lane <key>
_Written <YYYY-MM-DD HH:MM> by /session-it. Read this file in full before continuing work._

<!-- Lane identity. Do not edit by hand; /session-it maintains this block. -->
- **Session chain:** <oldest-uuid> -> <...> -> <current-uuid>
- **Transcript:** ~/.claude/projects/<slug>/<current-uuid>.jsonl
- **Working directory:** <absolute path>
- **Git:** branch `<branch>`<, worktree `<path>` if applicable>
- **Other lanes in this folder:** <count> (not read; see `/session-it list`)

## 1. Goal
<What we are ultimately building/fixing, in 1-3 sentences. Include acceptance criteria if known.>

## 2. Current State
<Where things stand: what works, what's broken, what's half-done. Branch name,
uncommitted-changes status, whether the app/tests currently run.>

## 3. Active Files
- `path/to/file` -- <why it's in play>
- ...

## 4. Changes Made
- <change> (<committed as `abc1234` | uncommitted>)
- ...

## 5. Failed Approaches -- DO NOT RETRY
- **<approach>** -- assumed <assumption>; failed because <evidence>. Conclusion: <what this rules out>.
- ...

## 6. Next Steps
1. <the step that was in progress -- with enough detail to resume mid-thought>
2. <subsequent steps in order>
```

Rules:
- Facts only -- every claim traceable to this conversation or a command you just ran. No
  speculation dressed as state.
- **Scope every claim to this lane.** If the working tree contains changes another session
  made, say so explicitly rather than listing them as yours: "uncommitted changes in
  `foo.py` are not from this session."
- Specific over complete: five precise bullets beat twenty vague ones.
- Plain language; the reader may be a fresh session with zero context OR the user days later.
- Empty section -> write "None this session", never delete the section.

</step>

<step name="handoff">

**Confirm and hand the user the reset procedure:**

```
Lane saved -- .handoffs/handoff-<key>.md

  Session: <full-uuid><, inferred by mtime -- unconfirmed> 
  Goal: <one line>
  Failed approaches captured: <N>
  Next step on deck: <one line>
  Other lanes here: <N> (untouched)

To reset context now:   type /clear, then "/session-it resume <key>"
To step away instead:   you're safe to close this session anytime
To see every lane:      /session-it list
```

The `/session-it resume <key>` line matters: `/clear` starts a new session UUID, so a fresh
session will NOT find this lane automatically. Always print the key.

Keep it to roughly that. Do not start new work, do not suggest features, do not re-explain
what was saved.

</step>

</process>

<guardrails>

- NEVER commit, push, stop containers, or modify code -- this skill writes only inside
  `.handoffs/`, plus one `.gitignore` line.
- NEVER touch `handoff.md` or `.handoff-history.md`. Those belong to /clear-it and the two
  skills are independent by design.
- NEVER write to a lane this session does not own. Ownership means the lane's `Session
  chain` lists the current session UUID.
- NEVER read another lane's body. Metadata only -- filename, Goal line, timestamp, branch.
- NEVER merge, rename, or delete a lane on your own initiative, including stale ones.
- NEVER overwrite an existing lane without archiving it to its own history file first.
- NEVER pad Failed Approaches with filler -- an inaccurate dead-end list is worse than none,
  because the next session will trust it.
- If session identity could not be confirmed (fallback 3 or 4 above), SAY SO in the final
  output. A lane written under a guessed identity is the one thing that can reintroduce
  cross-session mixing.
- If the project root is unclear (no git repo, no obvious markers), ask the user where to
  put `.handoffs/` rather than guessing.

</guardrails>

<relationship_to_clear_it>

Use `/clear-it` when one session works in a folder. Use `/session-it` when more than one
does. If you are unsure, `/session-it list` is harmless and tells you how many lanes exist.

They can coexist in the same repository and never touch each other's files. If a folder has
both a `handoff.md` and a `.handoffs/` directory, that is not an error -- it means someone
used /clear-it before the folder went multi-session. Mention it once; do not migrate it.

</relationship_to_clear_it>
