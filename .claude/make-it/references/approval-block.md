# The Approval Block (how a skill asks, and what an agent discloses)

The working form of "Keep the human able to notice" (`human-in-the-loop.md`, rules 1, 2, 3 and
5) for every skill with an approval point and every agent a skill dispatches. A skill links this
file from its `<execution_context>`; agent prompts carry the disclosure line themselves.

## Pick the tier before you ask

| Tier | What it is | How |
|------|-----------|-----|
| **Routine** | Reversible, expected, inside the task's scope | Don't ask. Do it, say so in one line, and list it in the end-of-run summary. |
| **Consequential** | Changes what ships, costs real time or money, or is awkward to undo | One ask: batch every such question of this step together. |
| **High-stakes** | Destructive or hard to undo; auth, permissions, secrets; schema or migrations; live data; money; anything sent outside the team; breaking changes | **Active confirmation:** the human states or picks the specific -- the count, the target, the case -- never a plain yes. This gate is never batched away or removed. |

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
rows, which environment) or the human types them.

## Agents disclose every safeguard they bypassed or weakened

Every agent and subagent report ends with one line: `SAFEGUARDS: none` -- or each one, with
what, where, and why. It counts:
- `--no-verify`, or any hook or check skipped;
- a test skipped, disabled, deleted, or loosened (a weaker assertion, a wider tolerance, a
  changed expected value) -- tests outside the task included;
- an edited hook, linter rule, CI step, evaluator, threshold, or coverage floor;
- widened permissions or scopes.

Mentioning it elsewhere in the report ("tidied a test") doesn't count; it goes on the line.
Disclosed is not approved -- the reviewer and the human still judge it. **Undisclosed is a
Critical finding.** Reviewers -- the SDD task reviewer, the adversarial reviewer, and
dispatch-it's integration step -- check every weakening in the diff against that line.
