# Make-It Deployment Lifecycle -- Sequence Diagrams

## Current State (What Works Today)

No security scanner is deployed to the cloud. CI/CD automation does not exist. The user's world stops at /ship-it creating a PR -- everything after that is manual.

```mermaid
sequenceDiagram
    actor User as Vibe Coder
    participant MI as /make-it
    participant Docker as Docker Sandbox
    participant TI as /try-it
    participant GH as GitHub
    participant RI as /resume-it
    participant SI as /ship-it

    Note over User,SI: === PHASE 1: BUILD ===

    User->>MI: /make-it
    MI->>User: What's your app idea?
    User->>MI: Describes idea in plain English

    loop Ideation Q&A
        MI->>User: Clarifying question
        User->>MI: Answer
    end

    MI->>MI: Design phase (invisible to user)
    MI->>User: "Here's what I'll build for you..."
    User->>MI: Confirms

    MI->>Docker: Generate code + build containers
    MI->>Docker: Build-verify (silent quality gate)
    Docker-->>MI: All checks pass

    Note over User,SI: === PHASE 2: VERIFY ===

    MI->>User: "Your app is ready! Run /try-it"
    User->>TI: /try-it
    TI->>Docker: Start containers (if not running)
    TI->>Docker: Smoke test (health, login, pages)
    Docker-->>TI: Results
    TI->>User: "Here's your app! Open browser to localhost:XXXX"

    User->>User: Explores app in browser

    Note over User,SI: === PHASE 3: ITERATE ===

    User->>RI: /resume-it
    RI->>RI: Context discovery (state, git log, TODO)
    RI->>User: "Welcome back! Here's where things stand..."

    alt User wants changes
        User->>RI: "I want to add/change X"
        RI->>Docker: Implement changes
        RI->>Docker: Run tests
        RI->>User: "Done! Run /try-it to check"
        User->>TI: /try-it
        User->>User: Verifies app works
    end

    RI->>GH: git push (code saved)

    Note over User,SI: === PHASE 4: SHIP (current gap) ===

    User->>SI: /ship-it
    SI->>GH: Create branch, commit, push
    SI->>GH: Create PR with labels + reviewers
    SI->>User: "Done! The team will take it from here."

    Note over GH: PR sits waiting for manual review
    Note over GH: No automated scanning
    Note over GH: No automated deployment
    Note over GH: DevOps reviews manually (if/when they get to it)
```

## Full Vision (Target State)

Security scanner deployed to cloud, scanning repos continuously. CI/CD automation operational. End-to-end from idea to production with the user only verifying at checkpoints.

```mermaid
sequenceDiagram
    actor User as Vibe Coder
    participant MI as /make-it
    participant Docker as Docker Sandbox
    participant TI as /try-it
    participant GH as GitHub
    participant RI as /resume-it
    participant SI as /ship-it
    participant SCN as Security Scanner<br/>(Cloud)
    participant BOT as CI/CD Automation
    participant DEV as Dev Environment
    participant PROD as Production

    Note over User,PROD: === PHASE 1: BUILD ===

    User->>MI: /make-it
    MI->>User: What's your app idea?
    User->>MI: Describes idea in plain English

    loop Ideation Q&A
        MI->>User: Clarifying question
        User->>MI: Answer
    end

    MI->>MI: Design phase (invisible to user)
    MI->>User: "Here's what I'll build for you..."
    User->>MI: Confirms

    MI->>Docker: Generate code + Terraform + build containers
    MI->>Docker: Build-verify (silent quality gate)
    Docker-->>MI: All checks pass
    MI->>GH: git push

    Note over User,PROD: === PHASE 2: VERIFY ===

    MI->>User: "Your app is ready! Run /try-it"
    User->>TI: /try-it
    TI->>Docker: Start containers (if not running)
    TI->>Docker: Smoke test (health, login, pages)
    Docker-->>TI: Results
    TI->>User: "Here's your app! Open browser to localhost:XXXX"

    User->>User: Explores app in browser

    Note over User,PROD: === PHASE 3: CONTINUOUS QUALITY (invisible to user) ===

    GH--)SCN: Webhook: push event
    SCN->>SCN: Scan repo (security scanners)
    SCN->>SCN: AI triage + generate remediation diffs
    SCN->>GH: Create GitHub Issues (labeled by scanner + severity)

    Note over User,PROD: === PHASE 4: ITERATE ===

    User->>RI: /resume-it
    RI->>RI: Context discovery (state, git log, TODO)
    RI->>GH: gh issue list --label security-scanner --state open
    GH-->>RI: 3 open findings (1 critical, 2 medium)

    rect rgb(255, 240, 240)
        Note over RI,SCN: Security Scanner Remediation (automatic, before user work)
        RI->>SCN: GET /findings/{id} (with API key)
        SCN-->>RI: Finding detail + ai_remediation_diff
        RI->>Docker: Apply AI diff to codebase
        RI->>Docker: Run tests
        Docker-->>RI: Tests pass
        RI->>GH: git push (fix committed)
        RI->>SCN: PATCH /findings/{id}/status = resolved
        GH--)SCN: Webhook: push event
        SCN->>SCN: Rescan confirms fix
        SCN->>GH: Auto-close GitHub Issue
    end

    RI->>User: "Welcome back! Here's where things stand..."

    alt User wants changes
        User->>RI: "I want to add/change X"
        RI->>Docker: Implement changes
        RI->>Docker: Run tests
        RI->>User: "Done! Run /try-it to check"
        User->>TI: /try-it
        User->>User: Verifies app works
        RI->>GH: git push
        GH--)SCN: Webhook: push (triggers rescan)
    end

    alt Security fix changed app behavior
        RI->>User: "I made security updates. Run /try-it to verify"
        User->>TI: /try-it
        User->>User: Verifies app still works
    end

    Note over User,PROD: === PHASE 5: SHIP ===

    User->>SI: /ship-it
    SI->>GH: Create branch, commit, push
    SI->>GH: Create PR with labels + reviewers
    SI->>User: "Your app is being reviewed. We'll let you know!"

    Note over User,PROD: === PHASE 6: CI/CD PREFLIGHT (automated) ===

    GH--)BOT: PR created event
    BOT->>BOT: Scan PR (security, compliance, IaC, containers, config)

    alt Terraform present
        BOT->>BOT: terraform validate + terraform plan
        BOT->>GH: Post plan output as PR comment
    end

    alt Issues found (auto-remediable)
        BOT->>GH: Commit fixes to PR branch (dependency updates, lint, Dockerfile)
        BOT->>BOT: Re-scan
    end

    alt Issues found (needs human)
        BOT->>BOT: Flag for DevOps team
        Note over BOT: DevOps team reviews + fixes
        BOT->>GH: Commit fixes to PR branch
    end

    BOT->>GH: PR comment: "Updates made for security/compliance"
    BOT->>User: Notification: "Please verify your app still works"

    User->>TI: /try-it
    User->>User: Verifies app still works

    User->>SI: /ship-it (re-submit)
    SI->>GH: Push to PR branch
    GH--)BOT: New commits on PR

    BOT->>BOT: Re-scan
    BOT-->>GH: All checks pass

    Note over User,PROD: === PHASE 7: DEPLOY TO DEV ===

    BOT->>DEV: terraform apply (dev environment)
    BOT->>DEV: Deploy app to dev environment
    BOT->>User: "Your app is live in the dev environment!"

    User->>DEV: Tests app in dev environment
    User->>User: "Does it work how I want?"

    Note over User,PROD: === PHASE 8: PRODUCTION ===

    User->>SI: /ship-it (confirms prod-ready)

    BOT->>BOT: Production preflight (stricter checks)
    BOT->>BOT: DevOps team final review

    alt Passes
        BOT->>PROD: terraform apply (prod environment)
        BOT->>PROD: Deploy app to production
        BOT->>User: "Your app is live! Here's the URL."
    end

    alt Fails
        BOT->>GH: Remediate
        BOT->>User: "Please verify once more"
        User->>TI: /try-it
        Note over User,BOT: Loop until clean
    end
```

## Gap Analysis

What exists today vs what's needed for the full vision.

```mermaid
graph LR
    subgraph EXISTS["Exists Today"]
        style EXISTS fill:#d4edda
        A["/make-it skill"]
        B["/try-it skill"]
        C["/resume-it skill"]
        D["/ship-it skill"]
        E["Security scanner codebase"]
        F["Docker sandbox"]
        G["GitHub repos"]
    end

    subgraph BLOCKED["Blocked on DevOps"]
        style BLOCKED fill:#f8d7da
        H["CI/CD Automation"]
        I["Dev deployment pipeline"]
        J["Prod deployment pipeline"]
        K["Terraform apply pipeline"]
        L["PR auto-scan workflow"]
    end

    subgraph NEEDS_BUILD["Needs Build"]
        style NEEDS_BUILD fill:#fff3cd
        M["Security scanner cloud deploy"]
        N["Scanner: GitHub Issue creation"]
        O["Scanner: Issue auto-close"]
        P["Scanner: API key per-repo scoping"]
        Q["Scanner: Push webhook listener"]
    end

    subgraph CONFIG_ONLY["Config Only"]
        style CONFIG_ONLY fill:#cce5ff
        R["SECURITY_SCANNER_API_URL in .env"]
        S["SECURITY_SCANNER_API_KEY in .env"]
        T["GitHub webhook to scanner"]
    end

    A --> F
    B --> F
    C --> E
    D --> G
    E --> M
    M --> N
    M --> O
    M --> P
    M --> Q
    H --> I
    H --> J
    H --> K
    I --> L
```

## Dependency Chain (What Unblocks What)

```mermaid
graph TD
    A["Security scanner cloud deploy"] --> B["GitHub Issue creation feature"]
    A --> C["Push webhook listener"]
    B --> D["/resume-it reads Issues + calls API"]
    C --> E["Auto-rescan on push"]
    E --> F["Issue auto-close on resolved"]
    D --> G["Full automated remediation loop"]

    H["CI/CD Automation spec finalized"] --> I["DevOps team builds automation"]
    I --> J["PR auto-scan"]
    J --> K["Auto-remediation on PR"]
    K --> L["Deploy to dev pipeline"]
    L --> M["Deploy to prod pipeline"]

    G --> N["END-TO-END:<br/>Idea to Production"]
    M --> N

    style A fill:#fff3cd
    style B fill:#fff3cd
    style C fill:#fff3cd
    style E fill:#fff3cd
    style F fill:#fff3cd
    style D fill:#d4edda
    style G fill:#d4edda
    style H fill:#d4edda
    style I fill:#f8d7da
    style J fill:#f8d7da
    style K fill:#f8d7da
    style L fill:#f8d7da
    style M fill:#f8d7da
    style N fill:#e2e3e5

    classDef you fill:#fff3cd,stroke:#856404
    classDef devops fill:#f8d7da,stroke:#721c24
    classDef done fill:#d4edda,stroke:#155724
    classDef goal fill:#e2e3e5,stroke:#383d41
```

### Legend

| Color | Meaning |
|-------|---------|
| Green | Exists or ready to wire up |
| Yellow | Needs build (security scanner features) |
| Red | Blocked on DevOps team |
| Gray | End goal |

### Critical Path

The two tracks are **independent** -- you don't need CI/CD automation to get the security scanner working, and vice versa:

**Track 1 (Security Scanner -- unblocked now):**
1. Deploy security scanner to cloud
2. Build GitHub Issue creation feature
3. Build push webhook listener + auto-rescan
4. Build issue auto-close on resolved
5. Add API key per-repo scoping
6. Wire up /resume-it (already coded in the contract)

**Track 2 (CI/CD Automation -- blocked on DevOps):**
1. Finalize CI/CD automation spec (contract is defined in ship-it-guide.md)
2. DevOps team builds automation
3. PR scanning pipeline
4. Dev/prod deployment pipelines
5. Terraform apply automation

**Track 1 delivers:** Automated security remediation loop (scanner finds -> /resume-it fixes -> rescan confirms)

**Track 2 delivers:** Automated deployment pipeline (PR -> scan -> remediate -> deploy)

**Together they deliver:** Idea to production with zero manual technical work from the user.
