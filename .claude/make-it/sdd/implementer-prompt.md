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

## Ambiguity resolution
[Any ambiguity I noticed in the brief and how to resolve it. Omit if none.]

## How to work
1. If anything is unclear or under-specified, ASK before implementing — do not guess.
2. Implement test-first (TDD): write failing tests for the brief's requirements, then the code.
3. Build only what the brief requires — no extra flags, options, or scope (YAGNI).
4. Run the tests; iterate until they pass.
5. Self-review your own diff for spec gaps, dead code, and quality before reporting.
6. Commit your work (clear message). Stay on the current branch — never commit to main/master.

## Report
Write your FULL report to `[REPORT_PATH]` (what you built, decisions, test command + output,
self-review notes). In your reply to me, return ONLY:
- **STATUS:** one of DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- **COMMITS:** the short SHAs you created (`<base7>..<head7>`)
- **TESTS:** one line (e.g. "8/8 passing via `npm test foo`")
- **CONCERNS:** anything you flagged (or "none")

Status meanings: DONE = complete & verified · DONE_WITH_CONCERNS = done but you have doubts
(state them) · NEEDS_CONTEXT = missing info, say exactly what · BLOCKED = cannot proceed, say why.
