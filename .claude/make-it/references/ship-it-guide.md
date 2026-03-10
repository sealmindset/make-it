# /ship-it Integration Guide

This reference tells /make-it how and when to hand off to /ship-it for deployment.

---

## What /ship-it Does

/ship-it is a Claude Code skill that automates the entire path from local code to a production-ready pull request. The developer runs one command: `/ship-it`. That's it.

**Behind the scenes, /ship-it:**
1. Detects the repo, branch, auth status, and project type
2. Reads the DevOps-managed .ship-it.yml config
3. Creates a branch, commits changes, pushes
4. Generates a caller workflow referencing the org's shared reusable workflow
5. Creates a PR with labels, reviewers, description, and go-live checklist
6. Reports back: "Done! The team will let you know when it's live."

**Two modes:**
| Command | What it does |
|---------|-------------|
| `/ship-it` | Ship to production. Creates PR, assigns reviewers, full safety checks. |
| `/ship-it save` | Save work in progress. Commits, pushes, creates draft PR. No review. |

---

## When /make-it Hands Off to /ship-it

After the build phase completes and the user has a working local application, /make-it:

1. **Confirms the app works locally** -- asks the user to verify
2. **Explains what happens next** in plain language:
   - "Your app is ready to go live. I'll now help you get it deployed."
   - "This will create a pull request that your team can review and approve."
3. **Checks prerequisites:**
   - Git repo exists (should already from project setup)
   - Code is in a clean state
   - .gitignore is properly configured
4. **Invokes /ship-it** which handles everything else

---

## What the User Needs Before /ship-it

| Requirement | How to get it | One-time? |
|------------|--------------|-----------|
| Claude Code installed | Already have it (they're using /make-it) | Yes |
| /ship-it plugin installed | /make-it can guide installation | Yes |
| GitHub CLI (gh) installed | brew install gh | Yes |
| GitHub CLI authenticated | gh auth login | Yes |
| Git installed | Pre-installed on most systems | Yes |
| Code cloned locally | Already done during /make-it | Yes |

---

## Transition Script (what /make-it tells the user)

When transitioning from build to ship:

"Your application is built and working locally. The next step is getting it deployed so others can use it. I'm going to hand you off to /ship-it, which will handle all the deployment steps automatically -- creating a branch, pushing your code, setting up the pipeline, and creating a pull request for review.

All you need to do is type: /ship-it

If you want to save your progress first without deploying, type: /ship-it save"
