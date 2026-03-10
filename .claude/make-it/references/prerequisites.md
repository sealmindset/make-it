# Prerequisites Reference

These prerequisites MUST be satisfied before /make-it can build anything. The skill checks what it can automatically and guides the user through anything missing.

This is Phase 0 -- it runs BEFORE ideation begins.

---

## Access Prerequisites (require manual requests -- cannot be automated)

These are corporate access requests that take time to approve. The skill must check for these FIRST so the user isn't blocked mid-build.

### 1. Sleep Number VPN

**Why needed:** Required to access Claude Code, Azure, GitHub, and all development services.
**How to check:** Ask the user -- "Are you connected to the Sleep Number VPN right now?"
**If missing:**
- Navigate to the Identity Now request center
- Select "Request for Myself"
- Click "Entitlements" on the left menu
- Search for: `VPNPRD_USER_SSO`
- Select the group, comment: "Need to install software libraries to support"
- Click Save, then Review Request, then Submit Request

### 2. Local Admin Rights

**Why needed:** Required to install software (Docker, SDKs, development tools).
**How to check:** `groups $(whoami) 2>/dev/null | grep -q admin && echo "yes" || echo "no"`
**If missing:**
- Navigate to the ServiceNow portal
- Search for: `Local Admin Rights`
- Select your system
- Enter justification: "For local development"
- Click Submit
- Note: This is time-bound and will need to be re-requested when it expires
- Warning: Must be on VPN to receive the temporary password for privilege elevation

### 3. Zscaler DevOps Group

**Why needed:** During local development, you may need to temporarily disable Zscaler to avoid proxy interference with developer tools.
**How to check:** Ask the user if they have Zscaler DevOps access
**If missing:**
- Navigate to the Identity Now request center
- Select "Request for Myself"
- Click "Entitlements"
- Search for: `ZscalerPRD_DevopsZTunnel_AppC`
- Select the group, comment: "Need to install software libraries to support"
- Submit the request
- Note: Zscaler disablement is time-boxed to 15 minutes max. Use sparingly.

### 4. Azure Subscription (AI Foundry)

**Why needed:** Required to access Claude Code through the Azure AI Foundry platform.
**How to check:** `az account show 2>/dev/null | grep -q "AIFoundryDEV" && echo "yes" || echo "no"`
**If missing:**
- Access to `AIFoundryDEV_User_AppC` AD Group required
- Navigate to the Identity Now request center
- Select "Request for Myself"
- Click "Entitlements"
- Search for: `AIFoundryDEV_User_AppC`
- Select the group, comment: "Need access to AI Foundry for Claude Code"
- Submit the request
- Approval goes to designated approvers

### 5. GitHub Access

**Why needed:** All code must be stored in the company's approved Git repositories for backup, collaboration, version control, audit history, and security scanning.
**How to check:** `gh auth status 2>/dev/null`
**If missing:**
- Navigate to the Identity Now request center
- Select "Request for Myself"
- Click "Entitlements"
- Search for: `githubSleepNumberIncSCIMPRD_GithubRW_AppC`
- Select the group, comment: "Need to maintain my code in a repo"
- Submit the request
- Approval goes to designated approvers

---

## Tool Prerequisites (can be checked and installed automatically)

### 6. Docker

**Why needed:** Creates consistent local development environments that mirror production. Simplifies building, running, and testing services locally.
**How to check:** `docker --version 2>/dev/null`
**If missing (macOS):**
- Must have all access prerequisites above first
- Clone the Dockyard repository:
  ```bash
  mkdir -p ~/Documents/Github && cd ~/Documents/Github
  git clone https://github.com/SleepNumberInc/Dockyard.git
  cd Dockyard
  chmod +x setup-macos.sh
  ./setup-macos.sh
  ```
- Follow on-screen prompts (approve installs/permissions as requested)
- Restart Terminal after completion
- Verify install using post-install checks in Dockyard README.md
**If missing (Windows):** Not yet available -- work in progress.

### 7. Git

**Why needed:** Version control for all code.
**How to check:** `git --version 2>/dev/null`
**If missing:** Pre-installed on most macOS systems. If not: `xcode-select --install`

### 8. GitHub CLI (gh)

**Why needed:** Required by /ship-it for creating branches, PRs, and deployment.
**How to check:** `gh --version 2>/dev/null`
**If missing:** `brew install gh` then `gh auth login`

### 9. Claude Code

**Why needed:** This IS the development environment.
**How to check:** Already running if they're using /make-it
**Setup references:** Claude Setup for macOS / Claude Setup for Windows (from Quick Start guide)

### 10. Visual Studio Code (IDE)

**Why needed:** Code editor for viewing and optionally editing generated code.
**How to check:** `code --version 2>/dev/null`
**If missing:** Download from VS Code website or `brew install --cask visual-studio-code`

### 11. Azure Login

**Why needed:** Required for deploying to Azure cloud services.
**How to check:** `az account show 2>/dev/null`
**If missing:** `az login` (requires Azure subscription access from step 4)

---

## Preflight Check Order

The skill should check prerequisites in this order (fast checks first, then blocking checks):

1. **Instant checks (automated):**
   - Git installed?
   - Docker installed?
   - GitHub CLI installed and authenticated?
   - Azure CLI installed and logged in?
   - Claude Code running? (implicit -- they're here)

2. **Questions for the user (only if automated checks fail):**
   - "Are you on the Sleep Number VPN?"
   - "Do you have local admin rights on this machine?"

3. **Categorize results:**
   - **Ready:** All green -- proceed to ideation
   - **Quick fixes:** Tools missing but can be installed now (Docker, gh, etc.)
   - **Blockers:** Access requests needed (VPN, local admin, GitHub, Azure) -- these take time

---

## How to Present Results to the User

**If everything passes:**
"Great news -- your machine is all set up and ready to go! Let's start building your app."

**If quick fixes needed:**
"Almost there! I need to install a couple of things first. This will just take a minute..."
[Install automatically or guide them through it]

**If blockers exist:**
"Before we can start building, you'll need a few things set up on your account. Don't worry -- I'll walk you through each one. Some of these require approval, so they might take a day or two.

Here's what you need:
1. [List only what's missing]

Once everything is approved, come back and type /make-it again -- I'll pick up right where we left off!"
