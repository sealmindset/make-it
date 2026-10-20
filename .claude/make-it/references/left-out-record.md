# Left Out by Your Choice (the one record every skill reads)

When a user leaves an item out -- at /retrofit-it's plan ask, /resume-it's catch-up ask, or at
any point after -- that choice is written down once, and every skill after it (/resume-it,
/try-it, /ship-it) reads it the same way. Skills point at this file; they don't restate it.

## The left-out record

**Where:** the project's `.make-it-state.md`, in the section `## Left out by your choice`, one
line per item. Only entries go in this section; what follows starts with its own `## ` heading.
The skill that asked writes the line: /retrofit-it right after Phase 5 makes its branch or
worktree, before step 1 (Part E keeps it),
/resume-it at its catch-up. A change of mind at any point, a check-in included, is the user's
answer too: when they say "take it out", the skill they told takes it out and writes its line
then, with "(taken out)" after the date; if part of it stays in the app, the line names only what
it took out. A skill that rewrites `.make-it-state.md` keeps this section as it is; one that adds
the section, to an older file or in a new one, first moves the older left-out lines (read step 2)
into it. That skill also moves into the section each item step 2 read from TODO.md, starting the
file if there is none (the TODO.md line stays). Each item becomes one `- ` entry in the form below
(checks: the IDs any of its lines names, `none` when none does). A line with no date of its own
takes the date it is moved. TODO.md also lists each item, with what the user will handle
themselves; that is the user's to-do list, not the record.

**One entry:** the item in the words the user saw, the build-standards check IDs it covers
(`none` when it has none), and the date they left it out. After the date comes an optional
"(taken out)", which only a "take it out" writes. Read an entry with no marker, older ones
included, as left out at plan time (the plan or catch-up ask), not taken out.

```markdown
## Left out by your choice

- [the item, in the words the user saw] -- checks [IDs, e.g. A01-A10, or none] -- left out [YYYY-MM-DD] [(taken out), only for a take-out]
```

## How a skill reads it

1. Read `.make-it-state.md`. No file: only a TODO.md line (step 2) can name an item; with none,
   nothing is left out; go on, and don't ask about it.
2. Take each `- ` line under `## Left out by your choice`, up to the next `## ` heading. With no
   such section (a file written before it existed), only the shapes older skills wrote count: an
   older /retrofit-it Part E line, `- [item] -- left out by your choice` (the phrase right after
   ` -- ` following the item's name), and the TODO.md lines below. A status line, such as try-it's
   `- Result: ..., plus 1 item(s) left out by your choice` under `## Try-It Status`, never counts.
   Only while there is no section, a TODO.md line that says "left out by your choice" (an older
   /resume-it wrote only there) is an item too, and so is each line listed under a TODO.md heading
   that says it, one item per top-level `- ` line (its indented lines are part of it), up to the
   next heading of the same or higher level; the heading itself is never an item. No section and
   no such line elsewhere, or a section with no entries: nothing is left out. The same item read
   on two lines (an older state-file line and its TODO.md line) is one item: mentioned once, moved
   in as one entry.
3. A check, test, or fix belongs to an item when its ID is on the item's line, or when it tests
   what the item names (a test with no ID always goes by what it tests). A check that something
   the app already had (and the user did not take out) still works as it did before never
   belongs to a left-out item. The user took out only what a line marked "(taken out)" names. A
   fix belongs to the item its failure belongs to, and to any item whose code it would add. A
   failure that only a left-out item's code would fix belongs to that item too; a check that
   something the app already had (and the user did not take out) still works as it did before
   still never does.
4. Only the user's own answer brings an item back. A request in the user's own words for what an
   item names ("can I see who did what?") is their answer. Before building it, the skill asks one
   plain question to confirm it is that item (not needed when the user named the item itself); it
   never raises the item unasked (rule 1). That question is not the gate: applying the item goes
   through the same ask that the plan or catch-up ask would have used for it (its catch and its
   undo), at the tier `approval-block.md` gives that item on its own. A high-stakes item
   (sign-in, roles, anything `approval-block.md` calls high-stakes) gets active confirmation,
   never a plain yes. The skill that then applies it deletes every line step 2 read for it
   (under `## Left out by your choice`, or in an older file each line that says so) and the
   item's "left out by your choice" line in TODO.md (in a grouped list, its line under that
   heading). A user's word that they added an item themselves brings it back the same way: the
   skill they told deletes those lines. If they bring back only part of an item, that skill
   instead replaces every line step 2 read for it with one line for the part still left out (only
   that part's checks), and that part keeps its TODO.md line, narrowed the same way. The new line
   keeps the old one's date and its "(taken out)", if it had one. The heading stays, even with no
   entries left.

## The rule every reader follows

- **Mentioned, never offered.** Where the skill reports what is still open, name it once, in
  plain words: "[item] -- left out by your choice -- tell me if you want it added." It never
  goes in an ask (the ship ask below is an exception, and so are these: the automation's PR
  comment when the DevOps team fixes it; /retrofit-it's fresh-build stop at Very High risk, which
  names each left-out item; /retrofit-it's ask to pick again when a left-out item is needed by one
  they kept; read step 4's one confirming question), a must-do or improvements group, or a list of
  suggestions.
- **Never FAIL.** A check or test that belongs to it, or whose failure does, reads **Left out
  (your choice)**. It is never counted in "X of Y" and never listed under Issues Found. It is
  never reported as passed either: say what could not be checked because of it.
- **Never put back on its own.** In any phase, no auto-fix, no fix in app code, and nothing
  generated for it. A failure that belongs to it is reported, not fixed, and never blocks a step --
  except a found secret: /ship-it stops and sends nothing (`ship-it-guide.md`, Left-out items
  before production).
- **At ship, named.** An item is a `[BLOCK]` item when any check that belongs to it, or whose
  failure does (read step 3), is `[BLOCK]` in `build-standards.md`. A left-out `[BLOCK]` item is never silently
  blocked and never silently passed: /ship-it names each one in its high-stakes ask
  (`approval-block.md`) -- the item, what it guards, and that the user left it out -- and the
  user picks. The choices and the words of the ask are in `ship-it-guide.md` (Left-out items
  before production).
