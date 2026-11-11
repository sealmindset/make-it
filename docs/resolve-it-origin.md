# Why /resolve-it exists

Not loaded at run time (so no past answer primes an investigation).

2026-11-11: one person's report ("the county's evidence still isn't in") took five stacked causes to
resolve over five days: a login saved under the vendor's shared sign-in address; a one-try sign-in
window that closed before a cold worker had booted; an intake that dropped the system's own export
emails as unknown senders; a mail redirect that hid the sender's authentication; and a worker that
dropped its own protection between two jobs. Each cause hid the next. `/debug-it` found each one;
nothing carried the loop from the report to the person's outcome, or kept the lessons. A blind dry
run of the first version found 13 gaps (forward walk, prior fixes, deleted evidence, confirm before
match, alerts that reach no one, ...), all folded into v1.52.0 before release.
