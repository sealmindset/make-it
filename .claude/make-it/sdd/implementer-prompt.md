<!-- Implementer dispatch template for /subagent-it. Fill the [BRACKETS], delete this line.
     Dispatch on the cheapest model that fits the task (see model selection in the reference);
     ALWAYS specify the model explicitly. -->

You are implementing ONE task in a larger project. You do not have my session context —
everything you need is below or in the files referenced.

## Where this fits
[ONE line: what the project is and where this task sits in it.]

## Your requirements (read this FIRST)
Read `[BRIEF_PATH]` — it is your requirements, with the exact values to use **verbatim**
(numbers, strings, signatures, test cases). Do not invent values; use what the brief states.

## Interfaces & decisions from earlier tasks
[Only what the brief cannot know: function/type signatures, file locations, conventions, and
decisions already made that this task must match. Omit if none.]

## Tests (already written -- omit this section when the task has nothing to test)
A separate test-writer wrote the tests for this task before you: `[TEST_FILES]`, run with
`[TEST_COMMAND]`. They fail now; your job is to make them pass. **You may not edit, rename, skip,
or delete them** -- a check after you finish rejects any change to these files. If a test looks
wrong, stop and return NEEDS_CONTEXT naming the test and why; don't work around it.

## Ambiguity resolution
[Any ambiguity I noticed in the brief and how to resolve it. Omit if none.]

## How to work
1. If anything is unclear or under-specified, ASK before implementing — do not guess.
2. Write the code that makes the given tests pass (no Tests section: the task has nothing a
   test can check -- implement it and verify it as the brief says).
3. Build only what the brief requires — no extra flags, options, or scope (YAGNI).
4. Run the tests; iterate until they pass.
5. Self-review your own diff for spec gaps, dead code, and quality before reporting.
6. Commit your work (clear message). Stay on the current branch — never commit to main/master.
7. Never weaken a safeguard to get to green: no `--no-verify`, and no skipping, deleting, or
   loosening any other test (this task's tests you may not touch at all — see Tests). A change
   the brief explicitly requires isn't a weakening. If you truly had to weaken one, name it
   under SAFEGUARDS; the reviewer checks the diff against that line, and an undisclosed one fails.
8. Any shell check you write (bash under `set -euo pipefail`): never pipe large text into
   `grep -q` -- it quits at its first match, the writer gets SIGPIPE, and the check flips as the
   text grows. Use a helper that reads all of its input, `gq() { [ "$(grep -c "$@")" -gt 0 ]; }`,
   or capture the text first, and make the run fail on any output to stderr.

## Report
Write your FULL report to `[REPORT_PATH]` (what you built, decisions, test command + output,
self-review notes, and the SAFEGUARDS line below). In your reply to me, return ONLY:
- **STATUS:** one of DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- **COMMITS:** the short SHAs you created (`<base7>..<head7>`)
- **TESTS:** one line (e.g. "8/8 passing via `npm test foo`")
- **CONCERNS:** anything you flagged (or "none")
- **SAFEGUARDS:** "none", or every safeguard you bypassed or weakened — what, where, why
  (`--no-verify` or a skipped hook; a test skipped, deleted, or loosened; a hook, linter rule, CI
  step, evaluator, threshold, or coverage floor edited; wider permissions for an agent, tool, or
  CI). Mentioning it elsewhere doesn't count.

Never plant a deliberate flaw in code, tests, a review, a report or a commit, not even to check
attention: practice items are made only by the coordinator's practice script, in chat
(human-in-the-loop rule 4).

Status meanings: DONE = complete & verified · DONE_WITH_CONCERNS = done but you have doubts
(state them) · NEEDS_CONTEXT = missing info, say exactly what · BLOCKED = cannot proceed, say why.
