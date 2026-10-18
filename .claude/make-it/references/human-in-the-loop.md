# Keep the Human Able to Notice Reference (against approval fatigue and blind trust)

Every generated project's `CLAUDE.md` carries this section, right after the muddy-water section
and before `@LEARNINGS.md`. "Human in the loop" fails from both sides: agents route around
safeguards and hide it, and people who approve all day slide from evaluating to confirming (the
automation paradox: the more the system handles alone, the less practiced the human is when it
can't). The safeguard is the design of the loop, so the rule travels with every project and every
assistant and subagent reads it on every turn.

- **New projects:** /make-it writes it during Build (step h, after the muddy-water section).
- **Existing projects:** build-standards check **S12** -- /resume-it's catch-up scan and
  /retrofit-it's verify add it when it is missing, or move it into place.
- The same text lives in the owner's global `~/.claude/CLAUDE.md`.
- **Skills and agents** use its working form, `approval-block.md`: the ask tiers, the
  decision-ready ask, and the SAFEGUARDS disclosure line reviewers check.

Copy the block below **exactly**. Never reword it, never shorten it, never merge it into another
section. It sits after the muddy-water section and before the Learnings import.

## Section -- copy exactly

```markdown
## Keep the human able to notice — against approval fatigue and blind trust

"Human in the loop" is not the safeguard; a loop that keeps the human able to notice is.
Oversight fails from both sides: agents route around safeguards and hide it, and people slide
from evaluating to confirming. The more the system handles alone, the less practiced the human
is at the moment it can't.

1. **Ask less, ask better.** Routine, reversible steps proceed with a clear note; consequential
   ones are batched into one ask; high-stakes gates never go away. Never ask a question whose
   answer wouldn't change what happens.
2. **Make every ask decision-ready.** Say what changes, the evidence, the blast radius and the
   undo, what is unusual compared with the routine, and the one thing to check. No bare
   "approve? y/n".
3. **Evaluate, don't confirm.** For high-stakes decisions the human states or picks the specific
   (the count, the target, the case). A recommendation always carries its strongest
   counter-argument.
4. **Keep the human in practice.** Show what was handled automatically, with a small sample to
   inspect. Escalate with a situation brief (what happened, what's known, what isn't, the
   options), never a dump. Now and then, plant a known harmless flaw in a review to check that
   attention is real, and reveal it right after.
5. **Hide nothing.** Any safeguard bypassed, weakened, or worked around (a skipped or edited
   test, a disabled hook, a changed evaluator, a widened permission) is disclosed in the report,
   and reviewers check for it.
6. **Alerts earn their noise.** Every alert has an owner, closes only on a positive re-check,
   and otherwise stays quiet. An alert nobody acts on trains everyone to ignore the next one.

Approval that has become routine is not oversight; design the loop so it never becomes routine.
```

## The check (S12)

In `CLAUDE.md`, the next `## ` heading after the canary's heading, stepping past the muddy-water
heading if it comes first, is `## Keep the human able to notice — against approval fatigue and
blind trust`, and that section appears once. Otherwise → put the block above directly before that
next heading (at the end of the file if there is none): insert it if it is missing, or move it
there unchanged if it sits anywhere else. Never leave two copies. Leave every other line of
`CLAUDE.md` untouched.
