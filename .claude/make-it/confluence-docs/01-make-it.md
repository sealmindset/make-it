# /make-it — Turn an idea into working software, from a small tool to a full app

*Part of the [make-it framework](00-make-it-framework-overview.md).*

---

## What is it?

`/make-it` takes a first-time builder from a **raw idea** to **working, verified software** through a friendly conversation. You describe what you want in plain English; it handles everything technical behind the scenes.

The idea can be big or small. Most people use it to build **apps** — screens people click through, with logins. It also builds smaller things: a **command-line tool** (a tool you run by typing a command instead of clicking), a **service** that other systems call, a **library** (a reusable building block other software plugs in), or an **extension** (an add-on for a web browser or code editor). You don't have to know which one you need — it works that out from your answers.

> **In one sentence:** Tell it what you want to make, answer some easy questions, and get working software with the right foundations for what it is.

---

## What is it used for?

Creating something new from scratch. For example:

**Apps with screens and logins**
- "A tool where my team can submit and approve expense reports."
- "A website where customers can browse our products and book appointments."
- "An internal dashboard that shows our sales numbers."

**Smaller tools**
- "A command that checks our weekly export for missing fields and tells me what's wrong."
- "A service our other systems can call to look up a product's warranty terms."
- "Shared code our tools use so they all format customer addresses the same way."

It builds the whole thing. For an app, that's the screens people see, the logic behind them, the database, user logins, permissions, and the packaging needed to run it. For a smaller tool, it's the tool itself plus the basics every project gets: settings kept out of the code, no passwords saved in files, a change log, and a to-do list.

---

## Why do you need it?

Because building software normally requires a team and months of specialized work. `/make-it` compresses that into a conversation. You get:

- **Zero coding required.** You never see or write code during the questions.
- **Real, professional foundations.** Every project gets the safety basics. Apps also get logins, user roles/permissions, security, and containerization built in automatically — not bolted on later.
- **A verified result.** It doesn't just generate code and walk away; it tests what it built and fixes problems before handing it to you.

---

## Room to grow

Start small. Early on, `/make-it` finds out whether real people will use this soon or whether you're testing an idea first (if your answers haven't already made that clear, it asks). If you're testing an idea, it uses a lighter setup you can upgrade later.

If the idea takes off, you don't start over. The other skills pick it up from there — [`/resume-it`](02-resume-it.md) to add to it, [`/nemo-it`](08-nemo-it.md) and [`/fix-it`](09-fix-it.md) to make it safe, [`/ship-it`](06-ship-it.md) to put it live, and [`/argo-it`](07-argo-it.md) to run it at large scale. (See [Start small, build the house later](00-make-it-framework-overview.md#start-small-build-the-house-later) on the overview page.)

---

## How it helps you vibe code

This is the flagship "vibe coding" skill. You supply the vibe — the idea and the goals — and it makes **every technical decision for you**: what programming language, what database, how logins work, how data is protected. You answer plain-language questions like *"Who will use this?"* and *"What should they be able to do?"*, and it maps your answers to professional engineering choices invisibly.

---

## How to use it

In your terminal (or Claude Code), type:

```
/make-it
```

You can also give it a head start:

```
/make-it a tool for tracking customer support tickets
```

```
/make-it a command that checks our weekly export for missing fields
```

Then just **talk to it.** It asks one easy question at a time, celebrates your answers, and summarizes progress so you always know where you are.

**The five phases (all handled for you):**
1. **Preflight** — checks your computer has the standard tools it needs (such as git and Docker). This happens first, for every project, big or small.
2. **Ideation** — understands what you want to build.
3. **Design** — makes all the technical decisions from your answers, including which kind of software you need.
4. **Build** — generates it and **verifies it actually works**.
5. **Ship** — hands off to [`/ship-it`](06-ship-it.md) when you're ready to go live.

> 💡 **To update the framework itself**, type `/make-it update`.

---

## When to use it

- ✅ You have an idea and **nothing built yet** — whether it's a full app or a small tool.
- ✅ What you're making **will be run again, used by someone else, or will touch company data**.
- ✅ You want it built to professional standards without learning to code.

**When *not* to use it:**
- ❌ You already have an app → use [`/resume-it`](02-resume-it.md) to continue it, or [`/retrofit-it`](03-retrofit-it.md) to upgrade it.
- ❌ It's a **one-off job** — reword a document, tidy up one spreadsheet, answer a question about some data → just ask Claude Code directly. No skill needed.
- ❌ You're not making anything new — you need to fix a bug, organize your saved work, or carry out a plan → pick up the tool for that job. See [Tools you can use on their own](00-make-it-framework-overview.md#tools-you-can-use-on-their-own).

### What to expect, even for a small tool

`/make-it` treats everything it builds as something you'll keep. So even for a small tool:

- It **checks your computer first** — before it asks about your idea. It helps install anything missing; if something needs an access request, approval can take a day or two.
- It asks for the **3–5 most important things** your tool should do, and a **name** for it.
- It keeps a **change log** and a **to-do list** for the project from the start.

If that's more than the job needs, the job is probably a one-off — see above.

---

## What happens behind the scenes (optional reading)

- For web apps, it starts from a proven **starter template** and fills in your specifics.
- It runs a **quality checklist** — only the checks that apply to what you're building — plus a **live test** matched to what it built. For an app: logins work, every page loads, permissions are enforced. For a command-line tool: it runs with sample input, and its help works. It **auto-fixes** issues (up to 3 rounds) before you ever see the result.
- If what you're building uses AI, it automatically adds **AI safety controls** and tests them.

---

## Which expert does the AI become?

While building, the AI quietly figures out what kind of specialist your project needs most — based on what you described (payments? personal data? lots of users? heavy AI?) — and **builds and reviews the risky parts in that expert's role**, not as a generalist. You won't be asked anything; it just raises the quality bar where it matters. (See the [framework overview](00-make-it-framework-overview.md#the-ai-becomes-the-right-expert-for-each-job) for how this works across every skill.)

---

## Related skills

- [`/try-it`](04-try-it.md) — see and explore an app you just built.
- [`/resume-it`](02-resume-it.md) — pick your project back up later.
- [`/ship-it`](06-ship-it.md) — put it live.
- [`/wrap-it`](13-wrap-it.md) — end your session cleanly.
