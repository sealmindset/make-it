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
| `.make-it/ui-review/` | Review screenshots, script, `review.html` (regenerable) | ignored |

**The preview and design.md always agree.** Every agreed change -- a preview round, a Part 2 fix,
a "can't be built as shown" agreement -- updates both, so later features build on the truth.

## Part 1 -- preview (before building screens)

1. **Write `design.md`** from the ideation answers and `app-context.json` (no new questions):
   - `## Screens` -- per screen: name, id (kebab-case), route (e.g. `/recipes`), which roles see it,
     what it shows (fields or columns with realistic sample values), main actions.
   - `## Navigation` -- sidebar entries in order; the dashboard is the first screen.
   - `## Status` -- `Preview: draft` and `Screens as built: pending`.
   - /resume-it features: add or update a `## <Feature>` section with its own screens and its own
     `Preview:` / `Screens as built:` lines; leave the rest (and the app's Status) alone.
2. **Build the preview as ONE self-contained HTML file:**
   - Copy the `:root` and `.dark` token blocks from the app's `globals.css` (`frontend/app/` or
     `src/app/`). Before the app exists, copy them from
     `~/.claude/make-it/scaffolds/fastapi-nextjs/frontend/app/globals.css` (both scaffolds use the
     same tokens). System font stack. No external requests at all (no CDNs, web fonts, remote
     images) -- it must open offline and behind SSL-inspecting proxies.
   - Reproduce the shell the scaffold builds: sidebar (entries from design.md), header with
     breadcrumbs, quick-search box, light/dark toggle. Tables look like the DataTable: header row,
     filter row, "Showing 1-10 of N".
   - One `<section id="<screen-id>">` per screen, switched by `#screen-id` links (`:target` CSS or a
     few lines of inline JS); with no hash, the dashboard shows. Links and buttons between screens
     work; forms show their fields but do not submit. A thin banner at the top: "Preview -- sample
     data, nothing is saved".
   - Realistic sample data from the app's domain; never real personal data.
   - Screens = the app's own screens. The standard admin pages the scaffold provides (users, roles,
     settings, activity logs, AI instructions) appear only as greyed, unclickable sidebar entries.
   - /resume-it features: the existing shell plus only the new or changed screens.
   - `variant: mobile`: add `<meta name="viewport" content="width=device-width, initial-scale=1">`
     and collapse the sidebar behind a menu button below 1024px, as the scaffold does.
3. **Open it** (`open` on macOS, `xdg-open` on Linux, `start` on Windows) and ask one question:
   "I made a clickable preview of your app -- nothing is built yet. Click around. Does it look and
   work the way you pictured? Tell me anything you'd change."
4. **Changes** -> update the preview and design.md, re-open, ask again. Repeat until the user says
   yes. No cap: the user drives. Don't offer learnings here -- queue any reusable rule and offer it
   after the Part 2 yes (`learnings.md`).
5. **On yes:** set `Preview: approved <date> (round <N>)`. That yes is the go-ahead to build.

## Build to the preview

Build screens to match the approved preview and design.md: same screens, routes, fields/columns,
actions, labels, and navigation order. The preview is the layout contract; the scaffold's components
(DataTable, sidebar, forms) implement it. If something in the preview can't be built as shown, say
so in plain words and agree on the change (updating both files) before building it differently.
SDD: every UI task's brief names the preview file and its screen ids.

## Part 2 -- built screens (after they are built and verified)

1. After build-verify (/make-it) or once the feature's tests pass (/resume-it). Make sure
   `.make-it/ui-review/` is in `.gitignore` (add it if missing). Start the app the way /try-it does
   if it isn't running.
2. **Take the screenshots** at 1280x800 (`variant: mobile`: also 375x812), with Playwright the way
   /try-it gets it (`npx playwright install chromium` if missing; run from `e2e/` if the project has
   it, else from `.make-it/ui-review/` after `npm i playwright` there):
   - each preview screen: `npx playwright screenshot --viewport-size=1280,800
     "file://<project>/.make-it/prototypes/<file>.html#<screen-id>" <screen-id>-preview.png`
   - each built screen, signed in: a small script in `.make-it/ui-review/`, one browser context per
     role, that signs in through the mock sign-in page and visits each screen's route:
     ```js
     await page.goto(`${FRONTEND_URL}/api/auth/login`);
     await page.click(`button[name="sub"][value="${mockUser}"]`); // mock-oidc user for that role
     await page.waitForURL(u => u.href.startsWith(FRONTEND_URL) && !u.pathname.startsWith('/api/'));
     for (const s of screens) {
       await page.goto(FRONTEND_URL + s.route);
       await page.waitForLoadState('networkidle');
       await page.screenshot({ path: `${s.id}-built.png` });
     }
     ```
     Use the same role -> mock user mapping as /try-it's smoke test. Keep no saved sign-in state.
3. If a built screen is visibly missing something its preview has, fix it and retake before showing
   anything -- the user never sees a broken screen.
4. Write `.make-it/ui-review/review.html`: one row per screen, captioned with the screen name, two
   columns -- "The preview you approved" | "What I built" -- images by relative path. Open it.
5. Ask one question: "Here's what I built, next to the preview you approved. Does it look right?
   Tell me anything you'd change." Changes -> fix (updating the preview and design.md if the
   agreed look changed), retake, regenerate, ask again. Yes -> set `Screens as built: approved
   <date>`.
6. Then offer the learnings queued in Part 1 and Part 2, per `learnings.md` (its own question).

## Desktop / Cowork

Web apps take the handoff route there, so Part 1 runs in Desktop (write design.md and the preview,
present the file, repeat until approved) and the bundle carries both. Part 2 runs in Claude Code
during build-verify.

**Plan-only bundle without an approved preview** (made before the UI gate existed): run Part 1
before building. Projects built before the UI gate are not retro-fitted; the gate applies to their
new features only.

## Out of scope

Non-web project types; bug fixes that don't add or change a screen; pixel-perfect matching (the
review is the user's eye, not a diff tool).
