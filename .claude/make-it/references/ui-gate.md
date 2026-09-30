# UI Gate Reference

Web apps only (`project_type: web-app`; other types have no screens -- skip). The user approves how
the app looks twice: a clickable **preview** before any screen is built, and the **built screens**
after, shown next to the preview they approved. They never read code; they click and react.
No new ideation questions: the preview IS the question.

Say "preview" to the user -- never "prototype", "HTML", "mockup", or "screenshot diff".

## Files (in the project)

| Path | What | Git |
|------|------|-----|
| `.make-it/design.md` | The design record: screens, navigation, approval status | committed |
| `.make-it/prototypes/app.html` | The preview (/make-it); `<feature-slug>.html` for a /resume-it feature | committed |
| `.make-it/ui-review/` | Review screenshots + `review.html` (regenerable) | ignored |

## Part 1 -- preview (before building screens)

1. **Write `design.md`** from the ideation answers and `app-context.json` (no new questions):
   - `## Screens` -- per screen: name, id (kebab-case), which roles see it, what it shows (fields or
     columns with realistic sample values), main actions.
   - `## Navigation` -- sidebar entries in order.
   - `## Status` -- `Preview: draft` and `Screens as built: pending`.
   - /resume-it features: add or update a `## <Feature>` section only; keep the rest.
2. **Build the preview as ONE self-contained HTML file:**
   - Copy the `:root` and `.dark` token blocks from the app's `globals.css` (`frontend/app/` or
     `src/app/`; before the build exists, the scaffold's copy under `~/.claude/make-it/scaffolds/`),
     so the colors are the ones that get built. System font stack. No external requests at all (no CDNs,
     web fonts, remote images) -- it must open offline and behind SSL-inspecting proxies.
   - Reproduce the shell the scaffold builds: sidebar (entries from design.md), header with
     breadcrumbs, quick-search box, light/dark toggle. Tables look like the DataTable: header row,
     filter row, "Showing 1-10 of N".
   - One `<section id="<screen-id>">` per screen, switched by `#screen-id` links (`:target` CSS or a
     few lines of inline JS); with no hash, the first screen shows. Links and buttons between screens work; forms show their fields but do
     not submit. A thin banner at the top: "Preview -- sample data, nothing is saved".
   - Realistic sample data from the app's domain; never real personal data.
   - Screens = the app's own screens. The standard admin pages the scaffold provides (users, roles,
     settings, activity logs, AI instructions) appear only as sidebar entries.
   - /resume-it features: the existing shell plus only the new or changed screens.
3. **Open it** (`open` on macOS, `xdg-open` on Linux, `start` on Windows) and ask one question:
   "I made a clickable preview of your app -- nothing is built yet. Click around. Does it look and
   work the way you pictured? Tell me anything you'd change."
4. **Changes** -> edit the file, re-open, ask again. Repeat until the user says yes. No cap: the
   user drives. A change that is a reusable rule -> offer it as a learning (`learnings.md`).
5. **On yes:** set `Preview: approved <date> (round <N>)` in design.md. That yes is the go-ahead to
   build.

## Build to the preview

Build screens to match the approved preview and design.md: same screens, fields/columns, actions,
labels, and navigation order. The preview is the layout contract; the scaffold's components
(DataTable, sidebar, forms) implement it. If something in the preview can't be built as shown, say
so in plain words and agree on the change before building it differently. SDD: every UI task's
brief names the preview file and its screen ids.

## Part 2 -- built screens (after they are built and verified)

1. After build-verify (/make-it) or once the feature's tests pass (/resume-it), with the app running,
   at a 1280x800 viewport, using Playwright the way /try-it does (`npx playwright install chromium`
   if it's missing):
   - each preview screen: `npx playwright screenshot --viewport-size=1280,800
     "file://$PWD/.make-it/prototypes/<file>.html#<screen-id>" .make-it/ui-review/<screen-id>-preview.png`
   - each built page, signed in as a role that uses it (reuse /try-it's smoke-test sign-in flow):
     `.make-it/ui-review/<screen-id>-built.png`
2. If a built screen is visibly missing something its preview has, fix it and retake before showing
   anything -- the user never sees a broken screen.
3. Write `.make-it/ui-review/review.html`: one row per screen, captioned with the screen name, two
   columns -- "The preview you approved" | "What I built" -- images by relative path. Open it.
4. Ask: "Here's what I built, next to the preview you approved. Does it look right? Tell me anything
   you'd change." Changes -> fix, retake, regenerate, ask again. Yes -> set
   `Screens as built: approved <date>` in design.md. Corrections that are reusable rules -> offer
   them as learnings.

## Desktop / Cowork

Web apps take the handoff route there, so Part 1 runs in Desktop (write design.md and the preview,
present the file, repeat until approved) and the bundle carries both. Part 2 runs in Claude Code
during build-verify.

**Build starting with no approved preview** (an older plan bundle, or a project built before the
UI gate): run Part 1 first.

## Out of scope

Non-web project types; bug fixes that don't add or change a screen; pixel-perfect matching (the
review is the user's eye, not a diff tool).
