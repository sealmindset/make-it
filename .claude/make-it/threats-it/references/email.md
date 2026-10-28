# Covering email (optional output — draft only, never send)

Use the sender's own email style if their memory or CLAUDE.md records one (`## Email style` in the organisation
profile). Default exec style: short paragraphs, **no bullets**, an aphorism or two, about 170 words maximum, plain
words, no headings. Executives strip structure and detail, so lead with the frame and the two findings that matter most.

Shape:
1. One-line frame (e.g. "I read the brief for how the attacks work, not which products they hit. Product lists change
   weekly. Attacker behaviour repeats.").
2. What the report does (chains, three questions: has it happened here, would we be alerted, how exposed are we).
3. The IOC verdict with its limit ("not the same as clean").
4. The one or two findings that matter more than any CVE (usually a detection gap and an exploited product in use).
5. Sign-off with the user's name.

Before handing it over, run the factual pass (standing rule): every figure, date, count and scope word in the
email must match the final derived data and the briefing; say which words were softened and why ("use" not "run"
when hosting is unproven). Report the word count. Use they/them for any recipient whose pronouns are unknown.

Hook, framing and analogy sentences are claims too: check them against the source like figures. A covering note once called memory disclosure a threat's "worst case" when the advisory's worst case was remote code execution; the first expert reader caught it. Present a side finding as its own issue instead of borrowing the hunted threat's urgency.
