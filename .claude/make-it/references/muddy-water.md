# Settle, Filter, Verify Reference (the muddy-water principle)

Every generated project's `CLAUDE.md` carries this section, right after the instruction-drift
canary and before `@LEARNINGS.md`. It is the order every change follows. Thrashing (fix on a
guess, fix on a fix, retry what just failed, change several things at once) makes a problem
worse; neglect (leaving stale alerts, open findings, unpatched gaps because they went quiet)
lets it rot. Writing it into the project means every assistant and subagent working there reads
it on every turn.

- **New projects:** /make-it writes it during Build (step h, after the canary).
- **Existing projects:** build-standards check **S11** -- /resume-it's catch-up scan and
  /retrofit-it's verify add it when it is missing.

Copy the block below **exactly**. Never reword it, never shorten it, never merge it into another
section. It sits after the canary and before the Learnings import; it never replaces either.

## Section -- copy exactly

```markdown
## Settle, filter, verify — the muddy-water principle

Thrashing makes things worse; neglect lets them rot. Every change, in this order:

1. **Settle.** Observe before touching: read the full error, reproduce it, gather evidence from
   ground truth, find the root cause. No fix on a guess, no fix on top of a fix, no retrying what
   just failed.
2. **Filter.** One small, reversible change at a time, with a known rollback. Never bypass a guard
   to "make it work".
3. **Verify.** Re-run the same reproduction, then check against reality — the real event, the real
   data, the system after it has propagated — before the next change and before claiming done,
   green, merged, or deployed. Silence is not proof; a quiet alarm is not a passing check.
4. **Don't mistake stillness for clean.** Latent risks (security gaps, stale alerts, unpatched
   findings, broken custody) don't settle on their own. Find and remove them deliberately; close
   only on a positive re-check.

A fix that hides the symptom without removing the cause is a clear-looking glass, not a clean one.
```

## The check (S11)

`CLAUDE.md` contains the line `## Settle, filter, verify — the muddy-water principle`. Missing →
insert the block above after the canary section and before `@LEARNINGS.md` (or at the end, if the
project has no Learnings import yet). Leave every other line of `CLAUDE.md` untouched.
