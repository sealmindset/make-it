# Which make-it Skill, When (Claude reaches for the skills on its own)

Every generated project's `CLAUDE.md` carries this section, right after the Learnings import. The
person building the app never has to learn the skills' names: any assistant working in the project
reads on every turn which skill fits which moment, and which skills it must never start on its own.

Two things make an assistant reach for a skill: the one-line description each skill carries (Claude
Code shows the assistant every installed skill with it), and a standing instruction in the project.
The descriptions say when to use each skill; this section is the standing instruction.

- **New projects:** /make-it writes it during Build (step h, after the Learnings import).
- **Existing projects:** build-standards check **S14** -- /resume-it's catch-up scan and
  /retrofit-it's verify add it when it is missing, and replace an older copy with this one.
- **A new skill** is added to the block here in the same change that adds its command;
  `scripts/test-skills-on-their-own.sh` fails until it is.

Copy the block below **exactly**. Never reword it, never shorten it, never merge it into another
section.

## Section -- copy exactly

```markdown
## Which make-it skill, when

The person never has to type a skill's name. Reach for the skill that fits, and say in one line
which one you started. A skill that is already running is not started again.

**Start it yourself, as part of the work:**
- A bug, a failing test or build, anything that behaves unexpectedly → `/debug-it`, before any fix.
- A git step on this computer (branch, commit, update, clean-up) → `/git-it`. A merge into the main
  branch, and anything sent to GitHub, waits for the person's go.
- Three or more unrelated failures → `/dispatch-it`; say how many agents before starting. An
  approved plan with several tasks → `/subagent-it`.
- The conversation is long and going in circles → offer `/clear-it`.

**Start it when the person's words ask for it, however they say it:**
- At the start of a session, or when no skill is running: "let's keep going", a new feature, a
  change → `/resume-it`.
- "Show me the app", "let me try it" → `/try-it`.
- "I'm done for today" → `/wrap-it`.
- "Keep track of this" → `/backlog-it`, when the project has a board.

**Suggest these, and start one only on a yes.** A no is kept: don't suggest it again unless
something has changed. `/make-it` (a brand-new app), `/retrofit-it` (bring an existing app up to
standard), `/nemo-it` (a security scan), `/fix-it` (fix what the scan found), `/deadcode-it`
(remove unused code), `/resolve-it --propose` (something a person needed did not happen,
especially after a first fix: it finds the cause, proposes the fix and waits).

**Never start these on your own.** They put the app in front of other people, send, or reach
outside this computer: `/ship-it`, `/argo-it`, `/demo-it`, `/threats-it`. Start one only when the
person asks for that outcome ("put it live", "send it to Kubernetes"), and keep every ask the skill makes.

A skill that isn't installed: say so in one line. For a never-start skill, stop there. For any
other, do the work by the same rule anyway.
```
