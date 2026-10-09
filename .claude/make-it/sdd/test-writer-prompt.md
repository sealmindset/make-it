<!-- Test-writer dispatch template for /subagent-it. Fill the [BRACKETS], delete this line.
     Dispatch on Sonnet (owner decision); ALWAYS specify the model explicitly. -->

You are writing the tests for ONE task in a larger project, BEFORE anyone writes the code. You do
not have my session context — everything you need is below or in the files referenced.

## Where this fits
[ONE line: what the project is and where this task sits in it.]

## The requirements to test (read this FIRST)
Read `[BRIEF_PATH]` — it is the task's requirements, with the exact values to use **verbatim**
(numbers, strings, signatures, test cases). Test what the brief requires; do not invent values.

## Interfaces & decisions from earlier tasks
[Only what the brief cannot know: function/type signatures, file locations, the test framework
and how the project runs its tests. Omit if none.]

## How to work
1. If anything is unclear or under-specified, ASK before writing tests — do not guess.
2. Write tests for **every** requirement in the brief, through its public interface (what a caller
   sees), not through internals the implementer hasn't written yet. Each test asserts something
   specific; no test that passes on an empty implementation.
3. Write **only** tests (and the smallest fixtures they need). No production code, no stubs of it.
4. Run them: they must **fail**, and for the right reason — the behavior is missing (assertion
   failure, missing function or module), not a broken test file (syntax error, bad import of the
   test framework).
5. Commit only your own files (`git add <files>`, clear message). Stay on the current branch —
   never commit to main/master.
6. Nothing in the brief can be checked by a test (docs, config, prompt wording)? Write nothing
   and report NOT_TESTABLE.

## Report
Write your FULL report to `[REPORT_PATH]` (each test and the requirement it covers, the test
command, the failing output). In your reply to me, return ONLY:
- **STATUS:** one of TESTS_READY / NOT_TESTABLE / NEEDS_CONTEXT / BLOCKED
- **COMMIT:** the short SHA of your test commit
- **TEST_FILES:** every file your commit touches -- tests and fixtures (repo-relative)
- **TEST_COMMAND:** the exact command that runs them
- **RED:** one line of the failing output (e.g. "3 failed: parse_date not defined")

Status meanings: TESTS_READY = tests committed and failing for the right reason · NOT_TESTABLE =
nothing to test, nothing written · NEEDS_CONTEXT = missing info, say exactly what · BLOCKED =
cannot proceed, say why.
