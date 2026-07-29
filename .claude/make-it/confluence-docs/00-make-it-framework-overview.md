# The make-it Framework — Overview

> **Copy-paste tip:** In Confluence Cloud, create a page, click **`•••` → Insert → Markdown** (or paste and choose "Convert to Confluence"). Each file in this folder is one Confluence page. Start with this page as the parent, then add the others as child pages.

---

## What is the make-it framework?

The **make-it framework** is a set of "skills" for Claude Code that let you build, test, secure, ship, and maintain real software **by describing what you want in plain English** — no coding knowledge required.

Each skill is a command you type that starts with a slash, like `/make-it` or `/ship-it`. You type the command, answer a few friendly questions, and Claude does the technical work behind the scenes.

Think of it as a **team of specialists on call**: one builds your app, one tests it, one checks it for security problems, one puts it live, one keeps your work organized. You never have to know how any of them do their job — you just ask.

---

## Why it exists

Normally, turning an idea into working, production-ready software takes a team of engineers weeks or months, and a lot of specialized vocabulary. The make-it framework compresses that into a **conversation**. It was designed for **"vibe coders"** — people with great ideas and zero programming background — while still producing software that meets real enterprise standards (security, logins, permissions, deployment).

**The promise:** you focus on *what* you want. The framework handles *how*.

---

## The skills at a glance

The skills fall into natural groups. Each has its own detailed page in this space.

### Build & grow your app
| Skill | One-liner |
|-------|-----------|
| [`/make-it`](01-make-it.md) | Build a brand-new app from an idea, start to finish. |
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
| [`/debug-it`](10-debug-it.md) | Find the *real* cause of a bug before changing anything. |
| [`/git-it`](11-git-it.md) | Keep your saved work clean, safe, and reversible. |
| [`/clear-it`](12-clear-it.md) | Save a checkpoint mid-session so Claude can reset and stay sharp. |
| [`/wrap-it`](13-wrap-it.md) | End your work session cleanly and save everything. |

### Power tools (advanced)
| Skill | One-liner |
|-------|-----------|
| [`/dispatch-it`](14-dispatch-it.md) | Fix several unrelated problems at the same time, in parallel. |
| [`/subagent-it`](15-subagent-it.md) | Execute a big multi-step plan automatically, with review after each step. |

---

## A typical journey

1. **`/make-it`** — describe your idea; Claude builds the whole app.
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
- **Enterprise-grade by default.** Logins, permissions, and security come standard, not as an afterthought.
- **You stay in control.** You approve plans before big changes happen.

---

## The AI becomes the right expert for each job

Here's something the framework does quietly in the background that makes a real difference to quality.

A general-purpose assistant is a jack-of-all-trades. But the *best* work on a risky task comes from a **specialist** — a security expert thinks differently than a database expert, who thinks differently than someone who keeps live systems running. So before the framework tackles high-stakes work, **it has the AI step into the role of the right specialist** for that exact job, instead of staying a generalist.

You don't ask for this and you won't see a prompt — it happens automatically, chosen from what your app actually involves (does it handle payments? personal data? thousands of users?). It simply means the AI brings the mindset — and produces the deliverables — of the specialist the work deserves.

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
- Already have an app? Start with [`/resume-it`](02-resume-it.md) or [`/retrofit-it`](03-retrofit-it.md).
- Just want to see something work? [`/try-it`](04-try-it.md).
- Worried about security? [`/nemo-it`](08-nemo-it.md).
