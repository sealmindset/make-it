# How our build framework compares to Anthropic's published playbook

**Leadership briefing — 23 September 2026**

Technical companion: **`docs/AI-NATIVE-SDLC-GAP-COMPANION.md`**
Source data appendix (machine-generated): **`docs/AI-NATIVE-SDLC-GAP-APPENDIX.md`**

Every number below appears in the companion with the same meaning and the same
denominator. Nothing here is rounded, softened, or estimated.

---

## 1. What are we talking about?

Software gets built in stages. Somebody has an idea. Somebody writes down what it
should do. Engineers build it. It gets tested. It gets released. Then it runs, and
people watch it for problems. Six stages. That sequence has been roughly the same
for thirty years.

What has changed is that an AI assistant can now do most of the building. That
speeds up the middle of the sequence enormously and leaves the rest of it — the
deciding, the approving, the checking — as the slow part.

Anthropic, the company that makes the AI assistant we use, has published a course
describing how they think the whole sequence should be rearranged now that the
building is fast. It is called the *AI-native SDLC Playbook*. SDLC means
"software development life cycle" — the six stages above. The course has 14
lessons. Two are an introduction and a conclusion and one is a completion page,
so **12 of them describe an actual practice**. We will call those 12 the *plays*.

We have our own framework, called **`/make-it`**. It is a set of written
instructions that tell the AI assistant how to build applications to our
standards — our security rules, our login approach, our infrastructure choices.
The point of `/make-it` is that a person with no programming background can
describe an application in plain English and get a working, standards-compliant
one back.

This briefing answers one question: **where does `/make-it` already do what the
playbook describes, and where does it not?**

### How we scored it

One direction only: we measured `/make-it` against the playbook. We did not
measure the playbook against `/make-it`. For each of the 12 plays we asked a
single yes/no question — *does our framework contain something that does this
job?* — and recorded one of three answers:

| Verdict | What it means | What we had to show to use it |
|---|---|---|
| **Present** | We have something that does this job | The name of the file that does it |
| **Partial** | We have something close, but it is missing one specific thing | The file, **and** the named missing piece |
| **Absent** | We have nothing that does this job | A search of the whole framework returning no results |

We have deliberately not used words like "weak" or "mature." They are opinions.
The three verdicts above are tests anyone can re-run.

**Result across the 12 plays: 4 Present, 3 Partial, 5 Absent.**

---

## 2. What is the problem?

Our framework is strong exactly where the playbook says the work is now easy, and
absent exactly where the playbook says the work has become the bottleneck.

### Where we are strong (the 4 Present)

We are ahead of the playbook on the act of building. The playbook tells you to
write down your standards and let the AI follow them. We have gone considerably
further: we ship **199 pre-built, already-debugged application files** that the
AI copies rather than re-creates, so the same bugs cannot come back. The playbook
has no equivalent idea. We also run multiple AI workers in parallel and we have
an automatic build-and-check-and-repair cycle. All of that is real and it works.

### Where the problem sits (the 5 Absent)

Five plays have no counterpart in our framework at all. Four of them share a
single root cause, which is worth stating plainly:

> **Our rules are written down, but nothing physically stops the AI from
> breaking them.**

Our framework contains **203 written rules that declare themselves mandatory** —
75 marked "must not proceed if this fails" and 128 marked "fix this
automatically." They are good rules. They are also, all 203 of them, just
paragraphs of English that we are asking the AI to read and obey.

The playbook's position on this is direct, and we quote it: *"A policy that must
always hold needs something deterministic behind the skill, such as a hook that
blocks the action."* A "hook" here is a small piece of software that sits in
front of the AI and physically refuses an action — it is a lock, as opposed to a
sign saying *please do not enter*.

**We have zero hooks.** Not a small number. Zero. Searched and confirmed.

So all 203 mandatory rules are signs, not locks. They work as long as the AI
reads them and complies, which it usually does. There is no mechanism that
catches the time it does not.

The three related absences follow from the same shape:

- **No regression testing of the framework itself.** Our framework is 599
  kilobytes of instructions across 15 files, plus 14 skills. When somebody edits
  those instructions — which we do regularly — nothing verifies that applications
  still build correctly afterwards. The playbook calls for a standing test suite
  of 20 to 50 real tasks that re-runs on every instruction change. We have **one**
  automated check in total, and it checks a file inventory, not behaviour.
- **No AI review of proposed changes.** We do run six automated checks before
  code is pushed, which is real and valuable. But nothing reviews the finished
  change against our written policy the way a reviewer would.
- **No measurement loop.** The playbook's final stage says: watch the running
  system, and when a number goes wrong, feed that back into the next round of
  work. Across our entire framework, the vocabulary of measurement — cycle time,
  error rates, baselines — appears on **2 lines, in 2 files**. There is no loop.

### The fifth absence is different

The playbook is built on a chain of small documents: an idea is written down as a
file, a named person approves it by merging it, and that merge is what starts the
next stage. The approvals are the record. Our framework has no such chain —
searching for all three of the playbook's document names returns **zero results**.

Instead, `/make-it` advances when a person types the next command. That is a
legitimate design for a tool aimed at someone building alone. It does mean there
is no written record of who decided what, which is the thing an auditor asks for.

---

## 3. What happens if we don't fix it?

Not a catastrophe. A slow, quiet accumulation of three specific costs.

**Cost one — the rules erode without anyone noticing.** Signs with no locks get
ignored eventually. A rule that is skipped once and produces no visible failure
gets skipped again. The cost is not the first skipped rule; it is that six months
later nobody can tell you which of the 203 rules are actually being followed, and
finding out means auditing generated applications one at a time by hand.

**Cost two — editing the framework gets slower and scarier.** Right now a change
to our instruction files is unverifiable. You make the edit, you hope, and you
find out when somebody builds an application. As the framework grows, the natural
response is to edit it less — which means our standards stop keeping up with our
practice. The clean-up is not a bug fix; it is building the missing test suite
later, under pressure, from a larger codebase than we have today.

**Cost three — we cannot answer the compliance question.** "Show me that the
security control was applied, and show me who approved it." Today the honest
answer is: the instructions say it should have been, and generally it was. That
answer does not survive an audit. Reconstructing the evidence after the fact is
substantially more expensive than recording it as we go, because it means
re-examining finished applications instead of capturing a decision at the moment
it was made.

None of these are urgent this quarter. All three get more expensive the longer
they wait, because the thing being audited or retro-fitted keeps growing.

---

## 4. Are there benefits beyond this?

Yes — three that pay off regardless of whether any of the risks above ever
materialise.

**Faster, more confident changes to the framework.** A regression suite is
usually sold as a safety net. Its larger effect is speed: when a change is
automatically verified, people make changes. The framework improves faster
because improving it stops being risky.

**Compliance evidence becomes a by-product instead of a project.** Hooks record
what they allowed and what they blocked, with timestamps. The approval chain
records who approved what. Neither is built *for* audit — they are built to make
the system work — but together they produce, for free, the evidence that audits
consume. The alternative is commissioning that evidence as its own piece of work,
repeatedly.

**Non-engineers get a way in.** The playbook's first stage lets anyone —
operations, support, finance — write down a problem and have it enter the work
queue as a proper document. Our framework is explicitly designed for people
without a technical background, so this fits us better than it fits most
organisations. We currently capture those conversations and discard them.

---

## 5. What is involved in resolving it?

Nothing needs to be purchased. Every piece of this uses tooling we already have
and already pay for. The work is sequenced so each step makes the next one safer.

| Step | What it is | Why this order |
|---|---|---|
| **1. Locks on the most important rules** | Turn a subset of the 75 "must not proceed" rules into software that physically blocks the action | Highest value per unit of effort; everything else is easier to trust once the rules are real |
| **2. A standing test suite** | 20–50 real build tasks that re-run automatically whenever the framework's instructions change | Makes steps 3 and 4 safe to attempt; our own change history supplies the test cases at no cost |
| **3. AI review on proposed changes** | An automated reviewer that checks each change against our written policy before a person sees it | Depends on step 1 existing, so the reviewer has firm rules to check against |
| **4. A written approval chain** | Capture the opening conversation as a document that a named person approves | Lowest technical difficulty, but changes how people work, so it goes last |

Rough shape of the effort: steps 1 and 2 are each a few days of one engineer's
time. Step 3 is largely configuration — a comparable setup already exists in
tooling cached on this machine and can be adapted rather than written. Step 4 is
mostly a process decision; the technical part is a document template.

We recommend doing steps 1 and 2 and then stopping to reassess. They are the two
that remove risk. Steps 3 and 4 add polish and audit evidence and can be judged
on their own merits once the first two are in place.

---

## 6. What we are not claiming

This section is a required part of the assessment, not a disclaimer.

**We are not claiming the framework is unsafe or that anything has gone wrong.**
We found no evidence of a rule being violated. We also did not look for one — this
assessment examined the framework's own files, not the applications it has
produced. *"No evidence that rules were broken"* is not the same statement as
*"rules were not broken."* Establishing the second would require reading the
generated applications, which live in other repositories we did not open.

**We are not claiming the playbook is correct.** It is one company's published
opinion, and it is the opinion of the company selling the assistant. Several of
its plays assume a large engineering organisation with dedicated platform and
security teams. Our framework is aimed at individuals with no technical
background. Where the two disagree, the playbook is not automatically right, and
in at least one area — the 199 pre-built application files — our approach solves
a problem the playbook does not address at all.

**"Absent" means absent from this repository, and nothing more.** Five plays
scored Absent. That verdict is based on searching the `/make-it` repository. Some
of the missing controls — in particular the enterprise-wide governance settings —
can only exist at the organisation level, and confirming their status requires
GitHub organisation administrator access and device-management administrator
access, neither of which we hold. For those, the accurate phrasing is
**unobserved**, not **not implemented**. The companion document names exactly
which privilege closes each of those gaps.

**The counts are counts of files and text matches, not of severity.** "203
mandatory rules with no enforcement" means 203 places where the text asserts a
rule. It does not mean 203 separate risks; several of them are restatements of
the same underlying control in different contexts. The companion separates them.

**We did not assess the quality of the 199 pre-built files.** We counted them and
confirmed they exist. Whether they are correct is a different question, and it is
precisely the question the missing test suite in step 2 would answer on an
ongoing basis.

---

*Figures in this briefing are derived from `docs/AI-NATIVE-SDLC-GAP-APPENDIX.md`,
which is generated from the repository by `docs/scripts/gen-sdlc-gap-appendix.sh`
and can be regenerated by anyone with a checkout.*
