# The make-it Framework — Overview

> **Copy-paste tip:** In Confluence Cloud, create a page, click **`•••` → Insert → Markdown** (or paste and choose "Convert to Confluence"). Each file in this folder is one Confluence page. Start with this page as the parent, then add the others as child pages.

---

## What is the make-it framework?

The **make-it framework** is a set of "skills" for Claude Code that let you build, test, secure, ship, and maintain real software **by describing what you want in plain English** — no coding knowledge required.

Each skill is a command you type that starts with a slash, like `/make-it` or `/ship-it`. You type the command, answer a few friendly questions, and Claude does the technical work behind the scenes.

Think of it as a **team of specialists on call**: one builds what you need, one tests it, one checks it for security problems, one puts it live, one keeps your work organized. You never have to know how any of them do their job — you just ask.

> **Not building an app?** Most of this still applies to you. See [Not building an app?](#not-building-an-app) below.

---

## Why it exists

Normally, turning an idea into working, production-ready software takes a team of engineers weeks or months, and a lot of specialized vocabulary. The make-it framework compresses that into a **conversation**. It was designed for **"vibe coders"** — people with great ideas and zero programming background — while still producing software that meets real enterprise standards (security, logins, permissions, deployment).

It works at more than one size. An idea can start as a **small tool that does one job** and grow, step by step, into a **system other people and teams rely on** — with a skill for each step along the way.

**The promise:** you focus on *what* you want. The framework handles *how*.

---

## Not building an app?

This is the most common question, so here is the straight answer.

### Think of it as a toolbox

A full toolbox has everything needed to **build a house**. But nobody says "I'm not building a house, so I don't need a hammer." Each tool also does its own job, on its own, on whatever project is in front of you.

The make-it framework works the same way:

- **Together**, the skills can take an idea all the way to a system the whole company relies on — that's the house.
- **On their own**, most of the skills do a useful job for any project, whether or not you're building an app.
- **They're already in the box.** When you need one, you pick it up. You don't have to go out and get one, or make your own from scratch — writing your own instructions for Claude and learning the same lessons the hard way. The skills carry what was learned on earlier builds, so the same mistakes aren't made twice.

### Tools you can use on their own

**For any project — no app needed:**

| Skill | Pick it up when… |
|-------|------------------|
| [`/debug-it`](10-debug-it.md) | Something is broken and you want the real cause before anything is changed. |
| [`/git-it`](11-git-it.md) | Your saved work needs organizing, or you're not sure what's safe to merge or delete. |
| [`/clear-it`](12-clear-it.md) | A long session has made Claude confused and you want a clean restart without losing your place. |
| [`/dispatch-it`](14-dispatch-it.md) | You have several unrelated problems to fix at the same time. |
| [`/subagent-it`](15-subagent-it.md) | You have an approved step-by-step plan and want it carried out with a review after each step. |

**For any app — including ones `/make-it` didn't build:**

| Skill | Pick it up when… |
|-------|------------------|
| [`/nemo-it`](08-nemo-it.md) → [`/fix-it`](09-fix-it.md) | You want an app checked for security problems, with a written report, then the problems fixed. |
| [`/retrofit-it`](03-retrofit-it.md) | An app built another way has grown, and now needs logins, permissions, and security. |
| [`/argo-it`](07-argo-it.md) | An app that already runs in containers (set up with Docker Compose) needs large-scale hosting (Kubernetes). |

### `/make-it` builds more than apps

When `/make-it` hears your idea, it works out which kind of software you need. It builds five kinds:

| Kind | In plain terms | Example idea |
|------|----------------|--------------|
| Web app | Screens people click through in a browser, usually with logins | "A tool where my team submits and approves expense reports." |
| Command-line tool | A tool you run by typing a command instead of clicking | "A command that checks our weekly export for missing fields and tells me what's wrong." |
| Service | Something other systems call to get an answer; it has no screens of its own | "A service our other systems can call to look up a product's warranty terms." |
| Library | A reusable building block that other software plugs in | "Shared code our tools use so they all format customer addresses the same way." |
| Extension | An add-on for a web browser or a code editor | "An add-on for our code editor that flags settings we're not allowed to use." |

You don't choose the kind — your answers decide it.

### Start small, build the house later

A small tool does not have to become a big one. But if it does, you don't start over — each stage has a tool:

| Stage | Skill | What it does |
|-------|-------|--------------|
| Try the idea | [`/make-it`](01-make-it.md) | Builds a working first version. Tell it you're testing an idea and it uses a lighter setup you can upgrade later. |
| Add to it | [`/resume-it`](02-resume-it.md) | Adds features, fixes problems, adds tests, and writes a checklist of what's left before it goes live. |
| Make it safe | [`/nemo-it`](08-nemo-it.md) → [`/fix-it`](09-fix-it.md) | Scans for security problems, writes a report, then fixes what it found. |
| Put it live | [`/ship-it`](06-ship-it.md) | Sends it to production as a change request that includes security checks and is reviewed before it goes live. |
| Run it at large scale | [`/argo-it`](07-argo-it.md) | Sets up large-scale hosting (Kubernetes) automatically. |

### Not every job needs a tool from the box

If the job is **truly one-off** — reword a document, tidy up one spreadsheet, answer a question about some data — just ask Claude Code directly. No skill needed.

Reach for `/make-it` once what you're making **will be run again, used by someone else, or will touch company data**. That is the point where a quick script becomes something that has to be kept safe and looked after, and `/make-it` builds it with those basics from the first day.

### What to expect from `/make-it`, even for a small tool

`/make-it` treats everything it builds as something you'll keep. So even for a small tool:

- It **checks your computer first** for its standard tools (such as git and Docker) — before it asks about your idea. It helps install anything missing; if something needs an access request, approval can take a day or two.
- It asks for the **3–5 most important things** your tool should do, and a **name** for it.
- It keeps a **change log** and a **to-do list** for the project from the start.

If that's more than the job needs, the job is probably a one-off — see above.

---

## The skills at a glance

The skills fall into natural groups. Each has its own detailed page in this space.

### Build & grow what you make
| Skill | One-liner |
|-------|-----------|
| [`/make-it`](01-make-it.md) | Turn an idea into working software — a small tool or a full app — start to finish. |
| [`/resume-it`](02-resume-it.md) | Come back to an existing app to add features, fix bugs, or test. |
| [`/retrofit-it`](03-retrofit-it.md) | Add enterprise foundations (login, permissions, security) to an app you already have. |

### See it working
| Skill | One-liner |
|-------|-----------|
| [`/try-it`](04-try-it.md) | Launch your app and test it automatically so you can click around and explore. |
| [`/demo-it`](05-demo-it.md) | Create and manage polished demo accounts for showing prospects (sales/onboarding). |

### Put it live
| Skill | One-liner |
|-------|-----------|
| [`/ship-it`](06-ship-it.md) | Send your app to production with one command. |
| [`/argo-it`](07-argo-it.md) | Deploy your app to Kubernetes (large-scale hosting) automatically. |

### Keep it safe
| Skill | One-liner |
|-------|-----------|
| [`/nemo-it`](08-nemo-it.md) | Scan your app for security and AI-safety problems and produce a report. |
| [`/fix-it`](09-fix-it.md) | Automatically fix the problems that `/nemo-it` found. |

### Work smarter & stay organized
| Skill | One-liner |
|-------|-----------|
| [`/debug-it`](10-debug-it.md) | Find the *real* cause of a bug before changing anything. Works in any project. |
| [`/git-it`](11-git-it.md) | Keep your saved work clean, safe, and reversible. Works in any project. |
| [`/clear-it`](12-clear-it.md) | Save a checkpoint mid-session so Claude can reset and stay sharp. Works in any project. |
| [`/wrap-it`](13-wrap-it.md) | End your work session cleanly and save everything. |

### Power tools (advanced)
| Skill | One-liner |
|-------|-----------|
| [`/dispatch-it`](14-dispatch-it.md) | Fix several unrelated problems at the same time, in parallel. Works in any project. |
| [`/subagent-it`](15-subagent-it.md) | Execute a big multi-step plan automatically, with review after each step. Works in any project. |

---

## A typical journey

1. **`/make-it`** — describe your idea; Claude builds it.
2. **`/try-it`** — Claude launches it so you can click around.
3. **`/resume-it`** — come back later to add features or fix things.
4. **`/nemo-it`** → **`/fix-it`** — scan for security issues, then fix them.
5. **`/ship-it`** — put it live.
6. **`/wrap-it`** — close up shop for the day.

You don't need to memorize this. Each skill tells you the natural next step when it finishes.

---

## What "vibe coding" means here

**Vibe coding** = building software by describing the *outcome you want* in everyday language, and letting the AI make all the technical decisions. The make-it framework is built for exactly this: every skill talks to you in plain language, never shows you raw code unless you ask, and never asks you to pick a framework or configure infrastructure.

---

## Ground rules the skills follow (so you can trust them)

- **No jargon.** If a technical word is unavoidable, it's explained immediately.
- **Nothing destructive without asking.** Anything hard to undo is confirmed first.
- **Enterprise-grade by default.** Every project gets the safety basics. Apps that people log into also get logins, permissions, and security as standard, not as an afterthought.
- **You stay in control.** You approve plans before big changes happen.

---

## The AI becomes the right expert for each job

Here's something the framework does quietly in the background that makes a real difference to quality.

A general-purpose assistant is a jack-of-all-trades. But the *best* work on a risky task comes from a **specialist** — a security expert thinks differently than a database expert, who thinks differently than someone who keeps live systems running. So before the framework tackles high-stakes work, **it has the AI step into the role of the right specialist** for that exact job, instead of staying a generalist.

You don't ask for this and you won't see a prompt — it happens automatically, chosen from what your project actually involves (does it handle payments? personal data? thousands of users?). It simply means the AI brings the mindset — and produces the deliverables — of the specialist the work deserves.

A few examples:

| When you run… | The AI works as a… | So it catches / delivers… |
|---|---|---|
| [`/debug-it`](10-debug-it.md) on a slow or flaky bug | reliability & performance engineer | the *real* root cause (not a band-aid), plus a test so it never comes back |
| [`/nemo-it`](08-nemo-it.md) / [`/fix-it`](09-fix-it.md) | security engineer | thinks like an attacker, fixes the cause, documents why it's safe |
| [`/argo-it`](07-argo-it.md) | platform/operations engineer | a plan for what happens if something breaks, not just "make it live" |
| [`/retrofit-it`](03-retrofit-it.md) | software architect | upgrades without breaking what already works |

If a task *isn't* risky, the AI stays a fast generalist on purpose — no ceremony where it isn't needed. This is the "team of specialists on call" idea made literal: the same assistant, wearing the right hat for each job.

---

## How to use these pages

- New to everything? Read [`/make-it`](01-make-it.md) first.
- Not building an app? Start with [Not building an app?](#not-building-an-app).
- Already have an app? Start with [`/resume-it`](02-resume-it.md) or [`/retrofit-it`](03-retrofit-it.md).
- Just want to see something work? [`/try-it`](04-try-it.md).
- Worried about security? [`/nemo-it`](08-nemo-it.md).
